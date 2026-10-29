//
//  Probe.swift
//  calendar-access
//

import AppKit
import CalendarAccessCore
import EventKit
import Security

/// Standard output only; the probe writes no file.
enum Output {
    static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

struct Options {
    enum Mode {
        case run(Variant)
        case selftest
        case verdict([String])
    }

    struct Problem: Error {
        let message: String
    }

    var mode: Mode
    /// Seconds to watch for store-change notifications.
    var watchSeconds = 60
    /// Seconds to wait for the request to return; 0 waits for ever (the prompt may be open).
    var waitSeconds = 0
    /// Whether to ask the maintainer about the prompt in an alert.
    var askAboutPrompt = true

    /// `variant=v1` comes from the arguments, or else from the end of the bundle identifier.
    static func parse(_ arguments: [String], bundleIdentifier: String?) -> Result<Options, Problem> {
        if arguments.first == "--selftest" {
            return .success(Options(mode: .selftest))
        }
        if arguments.first == "--verdict" {
            return .success(Options(mode: .verdict(Array(arguments.dropFirst()))))
        }
        var variant: Variant?
        var options = Options(mode: .selftest)
        for argument in arguments {
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                if argument.hasPrefix("-psn") { continue }
                return .failure(Problem(message: "unknown argument \(argument)"))
            }
            switch parts[0] {
            case "variant":
                guard let known = Variant(rawValue: parts[1]) else {
                    return .failure(Problem(message: "unknown variant \(parts[1])"))
                }
                variant = known
            case "watch":
                guard let seconds = Int(parts[1]), seconds >= 0 else {
                    return .failure(Problem(message: "watch needs a number of seconds"))
                }
                options.watchSeconds = seconds
            case "wait":
                guard let seconds = Int(parts[1]), seconds >= 0 else {
                    return .failure(Problem(message: "wait needs a number of seconds"))
                }
                options.waitSeconds = seconds
            case "alert":
                options.askAboutPrompt = parts[1] != "off"
            default:
                return .failure(Problem(message: "unknown argument \(argument)"))
            }
        }
        if variant == nil, let suffix = bundleIdentifier?.split(separator: ".").last {
            variant = Variant(rawValue: String(suffix))
        }
        guard let variant else { return .failure(Problem(message: "no variant")) }
        options.mode = .run(variant)
        return .success(options)
    }
}

/// Counts notifications from any thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let variant: Variant
    private let options: Options

    init(variant: Variant, options: Options) {
        self.variant = variant
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        Task { @MainActor in
            await Probe(variant: variant, options: options).run()
            exit(0)
        }
    }
}

@MainActor
struct Probe {
    let variant: Variant
    let options: Options

    private static let entitlement = "com.apple.security.personal-information.calendars"

    func run() async {
        let hardened = Probe.isHardened()
        let carries = Probe.carriesEntitlement()
        Output.emit(ReportLine.format(tag: "PROBE", [
            ("variant", variant.rawValue),
            ("bundle", Bundle.main.bundleIdentifier),
            ("hardened", hardened.map { $0 ? "yes" : "no" }),
            ("signed", variant.usesReleaseCertificate ? "release" : "adhoc"),
            ("entitlement", carries.map { $0 ? "calendars" : "none" }),
        ]))
        Output.emit(ReportLine.format(tag: "SYSTEM", [("macos", ProcessInfo.processInfo.operatingSystemVersionString)]))

        let memoryBefore = Probe.residentMegabytes()
        let store = EKEventStore()
        let statusBefore = Probe.status()
        Output.emit(ReportLine.format(tag: "STATUS", [("when", "before"), ("status", statusBefore.rawValue)]))

        let (granted, error) = await request(store)
        Output.emit(ReportLine.format(tag: "REQUEST", [("granted", granted ? "true" : "false"), ("error", error)]))

        let statusAfter = Probe.status()
        Output.emit(ReportLine.format(tag: "STATUS", [("when", "after"), ("status", statusAfter.rawValue)]))

        var readable = false
        if statusAfter == .fullAccess {
            let now = Date()
            let end = now.addingTimeInterval(7 * 24 * 3600)
            let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
            let calendars = store.calendars(for: .event).count
            let events = store.events(matching: predicate).count
            readable = true
            Output.emit(ReportLine.format(tag: "STORE", [("calendars", String(calendars)), ("events7d", String(events))]))
        } else {
            Output.emit(ReportLine.format(tag: "STORE", [("calendars", nil), ("events7d", nil)]))
        }

        await watchChanges(store)

        let memoryAfter = Probe.residentMegabytes()
        Output.emit(ReportLine.format(tag: "MEMORY", [
            ("beforeMB", memoryBefore.map { String(format: "%.1f", $0) }),
            ("afterMB", memoryAfter.map { String(format: "%.1f", $0) }),
        ]))

        askAboutPrompt()

        let observation = Observation(variant: variant, statusAfter: statusAfter, granted: granted, storeReadable: readable)
        Output.emit(ReportLine.format(tag: "SUMMARY", [("variant", variant.rawValue), ("outcome", observation.outcome.rawValue)]))
        Output.emit("=== end of report ===")
    }

    /// Asks for full access. A prompt that stays open is waited for, unless `wait=` limits it.
    private func request(_ store: EKEventStore) async -> (Bool, String?) {
        let box = Answer()
        Task { @MainActor in
            do {
                box.granted = try await store.requestFullAccessToEvents()
            } catch {
                let nsError = error as NSError
                box.error = "\(nsError.domain):\(nsError.code)"
            }
            box.done = true
        }
        var waited = 0
        while !box.done {
            if options.waitSeconds > 0, waited >= options.waitSeconds * 10 {
                return (false, "probe:timeout")
            }
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        return (box.granted, box.error)
    }

    private final class Answer {
        var granted = false
        var error: String?
        var done = false
    }

    private func watchChanges(_ store: EKEventStore) async {
        guard options.watchSeconds > 0 else {
            Output.emit(ReportLine.format(tag: "CHANGED", [("seen", nil), ("seconds", "0")]))
            return
        }
        let counter = Counter()
        let token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
            counter.increment()
        }
        Output.emit("STEP edit any event in Calendar within \(options.watchSeconds) seconds")
        try? await Task.sleep(for: .seconds(options.watchSeconds))
        NotificationCenter.default.removeObserver(token)
        Output.emit(ReportLine.format(tag: "CHANGED", [("seen", String(counter.count)), ("seconds", String(options.watchSeconds))]))
    }

    private func askAboutPrompt() {
        guard options.askAboutPrompt else {
            Output.emit(ReportLine.format(tag: "ANSWER", [("promptShown", nil), ("promptText", nil)]))
            return
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Did a macOS permission prompt appear?"
        alert.informativeText = "If yes, type what it said (one line)."
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        let shown = alert.runModal() == .alertFirstButtonReturn
        let text = field.stringValue.replacingOccurrences(of: "\n", with: " ")
        Output.emit(ReportLine.format(tag: "ANSWER", [
            ("promptShown", shown ? "yes" : "no"),
            ("promptText", shown && !text.isEmpty ? text : nil),
        ]))
    }

    // MARK: - Facts about the process

    private static func status() -> AccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .other
        }
    }

    /// Whether the running binary is signed with the hardened runtime (`CS_RUNTIME`).
    private static func isHardened() -> Bool? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let raw = dictionary[kSecCodeInfoFlags as String] as? UInt32 else { return nil }
        return raw & 0x10000 != 0
    }

    /// Whether the running process carries the Calendars entitlement.
    private static func carriesEntitlement() -> Bool? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        return (value as? Bool) == true
    }

    /// The resident size of the process in megabytes.
    private static func residentMegabytes() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1_048_576
    }

    // MARK: - Verdict without a permission

    /// Checks the verdict on built-in observations; no permission, no store.
    static func selftest() -> Bool {
        func seen(_ variant: Variant, _ outcome: Outcome) -> Observation {
            switch outcome {
            case .readable: Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: true)
            case .denied: Observation(variant: variant, statusAfter: .denied, granted: false, storeReadable: false)
            case .unreadable: Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: false)
            }
        }
        let cases: [(observations: [Observation], expected: Verdict.Result)] = [
            ([seen(.v1, .readable)], .entitlementNotNeeded),
            ([seen(.v1, .denied), seen(.v3, .readable)], .entitlementNotNeeded),
            ([seen(.v1, .denied), seen(.v2, .readable), seen(.v3, .denied)], .entitlementRequired),
            ([seen(.v3, .unreadable), seen(.v4, .readable)], .entitlementRequired),
            ([seen(.v4, .readable)], .entitlementRequired),
            (Variant.allCases.map { seen($0, .denied) }, .noGo),
            (Variant.allCases.map { seen($0, .unreadable) }, .noGo),
            ([], .noGo),
        ]
        var matches = true
        for entry in cases {
            let verdict = Verdict.evaluate(entry.observations)
            let names = entry.observations.map(\.variant.rawValue).joined(separator: ",")
            Output.emit(ReportLine.format(tag: "VERDICT", [("result", verdict.result.rawValue), ("variants", names)]))
            if verdict.result != entry.expected { matches = false }
        }
        Output.emit(matches ? "selftest ok" : "selftest MISMATCH")
        return matches
    }

    /// Reads the SUMMARY lines of finished reports and prints the verdict over them.
    static func verdict(ofFiles files: [String]) -> Int32 {
        var observations: [Observation] = []
        for file in files {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
                Output.emit("error: cannot read \(file)")
                return 2
            }
            for line in text.split(separator: "\n") where line.hasPrefix("SUMMARY ") {
                let fields = Dictionary(uniqueKeysWithValues: line.split(separator: " ").dropFirst().compactMap { pair -> (String, String)? in
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    return parts.count == 2 ? (parts[0], parts[1]) : nil
                })
                guard let variant = fields["variant"].flatMap(Variant.init(rawValue:)),
                      let outcome = fields["outcome"].flatMap(Outcome.init(rawValue:)) else { continue }
                switch outcome {
                case .readable:
                    observations.append(Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: true))
                case .denied:
                    observations.append(Observation(variant: variant, statusAfter: .denied, granted: false, storeReadable: false))
                case .unreadable:
                    observations.append(Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: false))
                }
            }
        }
        let result = Verdict.evaluate(observations)
        Output.emit(ReportLine.format(tag: "VERDICT", [
            ("result", result.result.rawValue),
            ("variants", observations.map(\.variant.rawValue).joined(separator: ",")),
        ]))
        Output.emit(result.reason)
        return 0
    }
}
