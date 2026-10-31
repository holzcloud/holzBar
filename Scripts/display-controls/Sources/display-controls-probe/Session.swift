//
//  Session.swift
//  display-controls
//
//  One run of the probe: the PROBE and SYSTEM lines, the command's lines, the SUMMARY built
//  from the verdicts of the core, the end-of-run questions and the end line. The probe reads
//  and measures; it changes a level only with `--allow-change`, restores it, prints no
//  display or device name unless `--show-values` is given and writes no file.
//

import Darwin
import DisplayProbeCore
import Foundation
import Security

/// Output goes through one lock and is written unbuffered, so a report that is cut off or
/// piped through `tee` is complete up to the last line.
enum Out {
    private static let lock = NSLock()

    static func emit(_ text: String) {
        lock.lock()
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        lock.unlock()
    }
}

enum Report {
    static let endLine = ProbeLine.endOfReport

    static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    static func level(_ value: Double) -> String { String(format: "%.4f", value) }

    static func millis(_ value: Double) -> String { String(format: "%.1f", value) }

    /// `ok` for the status 0, `err<status>` for anything else.
    static func status(_ value: Int32) -> String { value == 0 ? "ok" : "err\(value)" }
}

/// The options of one run.
struct Options {
    var command: String
    var label = "-"
    var allowChange = false
    var setValue: Double?
    var showValues = false
    var seconds = 60
}

/// The four values of the SUMMARY line a command measured; `nil` is written as `-`.
struct SummaryParts {
    var brightness: String?
    var volume: String?
    var listener: String?
    var external: String?
}

enum Session {
    static func run(_ options: Options) -> Int32 {
        PrivateBrightness.Restore.shared.installSignalHandlers()
        Out.emit(ProbeLine.line("PROBE", [
            ("mode", options.command),
            ("label", options.label),
            ("redact", Report.yesNo(!options.showValues)),
        ]))
        Out.emit(systemLine(showValues: options.showValues))

        var summary = SummaryParts()
        var answers = Answers()
        switch options.command {
        case "brightness":
            let outcome = runBrightness(options)
            summary = outcome.summary
            answers = outcome.answers
        case "displays":
            for display in Displays.list() {
                Out.emit(display.line)
            }
        case "volume":
            summary = runVolume(options)
        case "listen":
            summary.listener = Listen.run(seconds: options.seconds).rawValue
        default:
            break
        }

        Out.emit(ProbeLine.summary(
            brightness: summary.brightness,
            volume: summary.volume,
            listener: summary.listener,
            external: summary.external
        ))
        Out.emit(ProbeLine.line("ANSWER", [
            ("osdShown", answers.osdShown),
            ("autoBrightness", answers.autoBrightness),
            ("lowestVisible", answers.lowestVisible),
        ]))
        Out.emit(Report.endLine)
        return 0
    }

    // MARK: SYSTEM

    private static func systemLine(showValues: Bool) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macos = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        var machine = ProcessInfo.processInfo.machineArchitecture
        if showValues, let model = hardwareModel() {
            machine = "\(model)/\(machine)"
        }
        return ProbeLine.line("SYSTEM", [
            ("macos", macos),
            ("hardened", isHardened().map(Report.yesNo)),
            ("machine", machine),
        ])
    }

    /// The hardware model identifier (a model number such as `Mac15,3`, not a name).
    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Whether the running binary was signed with the hardened runtime.
    private static func isHardened() -> Bool? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let signingFlags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else {
            return nil
        }
        // kSecCodeSignatureRuntime
        return signingFlags & 0x10000 != 0
    }

    // MARK: brightness

    struct Answers {
        var osdShown: String?
        var autoBrightness: String?
        var lowestVisible: String?
    }

    private static func runBrightness(_ options: Options) -> (summary: SummaryParts, answers: Answers) {
        var summary = SummaryParts()
        var answers = Answers()
        let displays = Displays.list()
        for display in displays {
            Out.emit(display.line)
        }
        let symbols = PrivateBrightness.load()
        Out.emit(ProbeLine.line("PRIVATE", [
            ("loaded", Report.yesNo(symbols.loaded)),
            ("symbols", "\(symbols.symbols)/3"),
        ]))
        guard !displays.isEmpty else {
            Out.emit("STEP no active display was found")
            summary.brightness = Verdict.text((.noGo, "no active display"))
            return (summary, answers)
        }

        if let value = options.setValue {
            let display = displays.first { $0.builtIn } ?? displays[0]
            let measurement = PrivateBrightness.setOnce(display.id, value: value)
            Out.emit(brightnessLine(measurement))
            return (summary, answers)
        }

        if options.allowChange {
            Out.emit("STEP watch the screen: its brightness moves by 5 percent for under a second and goes back")
        }
        var measurements: [(display: DisplayInfo, measurement: PrivateBrightness.Measurement)] = []
        for display in displays {
            let measurement = PrivateBrightness.measure(display.id, allowChange: options.allowChange)
            Out.emit(brightnessLine(measurement))
            measurements.append((display, measurement))
        }

        // The result is judged on the built-in display, or on an Apple display that macOS
        // can change when the Mac has none.
        let judged = measurements.first { $0.display.builtIn }
            ?? measurements.first { $0.measurement.canChange == true }
            ?? measurements[0]
        summary.brightness = Verdict.text(Verdict.brightness(observation(judged.measurement, symbols: symbols)))
        let others = measurements.filter { !$0.display.builtIn && $0.measurement.canChange == true }
        summary.external = Verdict.externalList(others.map(\.display.id))

        if options.allowChange, measurements.contains(where: { $0.measurement.changeTested }) {
            answers = askBrightnessQuestions()
        }
        return (summary, answers)
    }

    static func observation(
        _ measurement: PrivateBrightness.Measurement,
        symbols: (loaded: Bool, symbols: Int)
    ) -> Verdict.BrightnessObservation {
        Verdict.BrightnessObservation(
            loaded: symbols.loaded,
            symbolsResolved: symbols.symbols,
            canChange: measurement.canChange,
            value: measurement.reading?.value,
            changeTested: measurement.changeTested,
            setSucceeded: measurement.setStatus.map { $0 == 0 },
            readBack: measurement.readBack,
            target: measurement.target,
            original: measurement.reading?.value,
            restored: measurement.restored,
            slowestCallMs: measurement.slowestMs
        )
    }

    static func brightnessLine(_ measurement: PrivateBrightness.Measurement) -> String {
        ProbeLine.line("BRIGHTNESS", [
            ("id", String(measurement.id)),
            ("canChange", measurement.canChange.map(Report.yesNo)),
            ("get", measurement.reading?.text),
            ("set", measurement.setStatus.map(Report.status)),
            ("readBack", measurement.readBack.map(Report.level)),
            ("restored", measurement.restored.map(Report.level)),
            ("ms", measurement.canChange == nil ? nil : Report.millis(measurement.slowestMs)),
        ])
    }

    // MARK: volume

    private static func runVolume(_ options: Options) -> SummaryParts {
        var summary = SummaryParts()
        guard let device = Volume.defaultOutputDevice() else {
            Out.emit(ProbeLine.line("VOLUME", [
                ("transport", nil), ("plan", nil), ("virtualMain", nil), ("channels", nil),
                ("muteSettable", nil), ("set", nil), ("readBack", nil), ("restored", nil),
            ]))
            summary.volume = Verdict.text((.noGo, "no default output device"))
            return summary
        }
        let transport = Volume.transport(of: device)
        if options.showValues, let name = Volume.name(of: device) {
            Out.emit(ProbeLine.line("STEP", [("outputDevice", name)]))
        }
        let plan = Volume.plan(for: device)
        if options.allowChange {
            Out.emit("STEP the output volume moves by 5 percent for under a second and goes back; you may hear it")
        }
        let change = options.allowChange ? Volume.changeTest(device, plan: plan) : Volume.ChangeOutcome()
        let tested = options.allowChange && change.original != nil
        Out.emit(ProbeLine.line("VOLUME", [
            ("transport", transport.rawValue),
            ("plan", plan.word.rawValue),
            ("virtualMain", plan.virtualMainState),
            ("channels", String(plan.settableChannels)),
            ("muteSettable", Report.yesNo(plan.muteSettable)),
            ("set", change.setStatus.map { Report.status($0) }),
            ("readBack", change.readBack.map(Report.level)),
            ("restored", change.restored.map(Report.level)),
        ]))
        let observation = Verdict.VolumeObservation(
            plan: plan.word,
            transport: transport,
            changeTested: tested,
            original: change.original,
            target: change.target,
            readBack: change.readBack,
            restored: change.restored,
            muteSettable: plan.muteSettable,
            listener: change.listener
        )
        summary.volume = Verdict.text(Verdict.volume(observation))
        summary.listener = change.listener.rawValue
        return summary
    }

    // MARK: Questions

    /// The end-of-run questions, asked only on a terminal.
    private static func askBrightnessQuestions() -> Answers {
        guard isatty(STDIN_FILENO) != 0 else {
            return Answers()
        }
        var answers = Answers()
        answers.osdShown = askYesNo("did the system's own brightness bar appear during the change test")
        answers.autoBrightness = askYesNo("was automatic brightness on")
        Out.emit("STEP optional, press Return to skip: the lowest brightness step at which the screen was still readable, in percent")
        if let line = readLine(), let number = Int(line.trimmingCharacters(in: .whitespaces)), (0...100).contains(number) {
            answers.lowestVisible = String(number)
        }
        return answers
    }

    private static func askYesNo(_ question: String) -> String? {
        Out.emit("STEP answer y or n and press Return: \(question)")
        switch readLine()?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "y", "yes": return "y"
        case "n", "no": return "n"
        default: return nil
        }
    }
}

extension ProcessInfo {
    /// `arm64` or `x86_64`.
    var machineArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

// MARK: selftest

enum Selftest {
    /// Runs the verdicts and the line format on built-in data: no display, no audio device
    /// and no permission. Exits 0 only when every line matches.
    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ name: String, _ actual: String, _ expected: String) {
            if actual != expected {
                failures.append("\(name): got \(actual) expected \(expected)")
            }
        }

        let fixture = Verdict.BrightnessObservation(
            loaded: true,
            symbolsResolved: 3,
            canChange: true,
            value: 0.62,
            changeTested: false,
            slowestCallMs: 4
        )
        let summary = ProbeLine.summary(
            brightness: Verdict.text(Verdict.brightness(fixture)),
            volume: nil,
            listener: nil,
            external: Verdict.externalList([])
        )
        check("summary", summary, "SUMMARY brightness=\"REDUCED-GO (read only)\" volume=- listener=- external=-")

        var changed = fixture
        changed.changeTested = true
        changed.setSucceeded = true
        changed.original = 0.62
        changed.target = 0.67
        changed.readBack = 0.67
        changed.restored = 0.62
        check("go", Verdict.text(Verdict.brightness(changed)), "GO")

        var missing = fixture
        missing.symbolsResolved = 2
        check("nogo", Verdict.text(Verdict.brightness(missing)), "NO-GO (only 2 of 3 symbols resolved)")

        let display = DisplayInfo(id: 1, builtIn: true, main: true, width: 3024, height: 1964)
        check("display", display.line, "DISPLAY id=1 builtIn=yes main=yes width=3024 height=1964")

        let line = Session.brightnessLine(PrivateBrightness.Measurement(id: 1, canChange: true))
        check("brightness", line, "BRIGHTNESS id=1 canChange=yes get=- set=- readBack=- restored=- ms=0.0")

        check("target", Report.level(Verdict.target(from: 0.62)), "0.6700")
        check("targetFloor", Report.level(Verdict.target(from: 0.0)), "0.0500")
        check("targetTop", Report.level(Verdict.target(from: 0.99)), "0.9400")

        let volume = Verdict.VolumeObservation(
            plan: .virtualMain,
            transport: .builtIn,
            changeTested: true,
            original: 0.5,
            target: 0.55,
            readBack: 0.55,
            restored: 0.5,
            muteSettable: true,
            listener: .fired
        )
        check("volumeGo", Verdict.text(Verdict.volume(volume)), "GO")
        var untested = volume
        untested.changeTested = false
        untested.listener = .notRun
        check("volumeReduced", Verdict.text(Verdict.volume(untested)), "REDUCED-GO (change not tested, listener not run)")
        check("volumeNone", Verdict.text(Verdict.volume(.init(plan: .none, transport: .builtIn))), "NO-GO (no settable volume)")
        check(
            "volumeLine",
            ProbeLine.summary(brightness: nil, volume: "GO", listener: Verdict.ListenerState.notRun.rawValue, external: nil),
            "SUMMARY brightness=- volume=GO listener=\"not run\" external=-"
        )

        if failures.isEmpty {
            Out.emit("selftest ok")
            return 0
        }
        for failure in failures {
            Out.emit("selftest FAIL \(failure)")
        }
        return 4
    }
}
