// What does the Dock expose to Accessibility about its application icons, and does it announce
// changes? Read-only: public Accessibility, AppKit and Foundation calls only. It sets no
// attribute, performs no action, posts no event, starts no process, opens no connection and
// writes no file.
//
// Run it on a Mac with Messages (or any app that shows a red badge on its Dock icon), three times:
//
//   swift Scripts/macos27/dock-badges-probe.swift 2>&1 | tee ~/Desktop/dock-tree.txt
//   swift Scripts/macos27/dock-badges-probe.swift --watch 120 2>&1 | tee ~/Desktop/dock-watch.txt
//
// For the second run: while it watches, let a message arrive in Messages and read another one,
// then run `killall Dock` once so that the probe can show that it follows the Dock's relaunch.
//
// The terminal needs Accessibility (System Settings > Privacy & Security > Accessibility).
//
// What a run does:
//   1. The macOS build and the Dock's process, the Dock's children down to its list, and for
//      every item of that list its role and subrole.
//   2. For every application item: its title, the bundle identifier of its URL, every attribute
//      name the Dock reports for it, and the value of each attribute that is a string, a number
//      or a Boolean (strings are cut at 40 characters, other kinds are named only).
//   3. A summary: how many application items there are, and every attribute name with the
//      number of application items that have it and the number on which it holds a value.
//   With --watch SECONDS it also:
//   4. Registers one Accessibility observer for the public notifications value changed, title
//      changed, created, destroyed, layout changed and selected children changed on the Dock,
//      its list and every application item, prints which registrations failed and with which
//      error, then prints every notification with the time, its name and the role, subrole and
//      title of the element, and what changed in that element's attribute values.
//   5. Follows a relaunch of the Dock: it says so, drops every element and registers again.
//   6. At the end it reads everything once more and says how many items changed without any
//      notification having told it.
//
// Options:
//   --watch <seconds>   observe notifications for this long after the first snapshot
//   --redact            replace the titles and bundle identifiers of non-Apple apps, and their
//                       long text values (short values such as a count stay readable)
//   --help
import AppKit
import ApplicationServices

// MARK: - Options and shared state

struct Options {
    var watch: Double?
    var redact = false
}

nonisolated(unsafe) var options = Options()
nonisolated(unsafe) var startUptime = ProcessInfo.processInfo.systemUptime
nonisolated(unsafe) var bundleAliases = [String: String]()

let dockBundleID = "com.apple.dock"
let messagingTimeout: Float = 0.25
let maxTextLength = 40
let maxRegistrationFailuresPrinted = 40

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--watch":
            guard let value = arguments.first, let seconds = Double(value), seconds > 0 else {
                print("--watch needs a number of seconds, see --help")
                exit(64)
            }
            parsed.watch = seconds
            arguments.removeFirst()
        case "--redact":
            parsed.redact = true
        case "--help", "-h":
            print("usage: swift dock-badges-probe.swift [--watch SECONDS] [--redact]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
    return parsed
}

func out(_ line: String) {
    print(line)
}

func elapsed() -> String {
    String(format: "t+%.2fs", ProcessInfo.processInfo.systemUptime - startUptime)
}

// MARK: - Formatting

func isApple(_ bundleID: String?) -> Bool {
    bundleID?.hasPrefix("com.apple.") ?? false
}

/// The key as it is printed: the real one, or `app<n>` for a non-Apple app with --redact
/// (numbered in the order first seen, consistent within one run only).
func shownKey(_ key: String) -> String {
    guard options.redact, !isApple(key) else {
        return key
    }
    if let alias = bundleAliases[key] {
        return alias
    }
    let alias = "app\(bundleAliases.count + 1)"
    bundleAliases[key] = alias
    return alias
}

func cut(_ text: String) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: "\\n")
    return flat.count > maxTextLength ? String(flat.prefix(maxTextLength)) + "..." : flat
}

func shownTitle(_ title: String?, owner: String?) -> String {
    guard let title else {
        return "-"
    }
    if options.redact, !isApple(owner) {
        return "<redacted>"
    }
    return "\"" + cut(title) + "\""
}

/// A text value as it is printed. With --redact a non-Apple app's text is hidden when it is
/// its title, contains its title or is longer than 12 characters; a short value such as a count stays.
func shownText(_ text: String, title: String?, owner: String?) -> String {
    if options.redact, !isApple(owner) {
        let mentionsTitle = title.map { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) } ?? false
        if mentionsTitle || text.count > 12 {
            return "\"<redacted>\""
        }
    }
    return "\"" + cut(text) + "\""
}

// MARK: - Accessibility helpers

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name), CFGetTypeID(value) == CFStringGetTypeID() else {
        return nil
    }
    let text = value as? String
    return text?.isEmpty == false ? text : nil
}

func children(of element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func attributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else {
        return []
    }
    return names as? [String] ?? []
}

/// The bundle identifier of the bundle that an element's URL points to.
func bundleIdentifier(ofURLIn element: AXUIElement) -> String? {
    guard let value = attribute(element, kAXURLAttribute), CFGetTypeID(value) == CFURLGetTypeID() else {
        return nil
    }
    // swiftlint:disable:next force_cast
    let url = (value as! CFURL) as URL
    return Bundle(url: url)?.bundleIdentifier
}

/// What one element's attributes say, read once.
struct AttributeReading {
    /// Every attribute name the element reports, in the order it reports them.
    var names = [String]()
    /// The printed form of every attribute, in the same order: the value of a string, number
    /// or Boolean, or the kind of anything else.
    var display = [(name: String, text: String)]()
    /// The raw values of the strings, numbers and Booleans, for comparing two readings.
    var values = [String: String]()
    /// The names of the attributes that hold a value.
    var holdsValue = Set<String>()
}

func readAttributes(of element: AXUIElement, title: String?, owner: String?) -> AttributeReading {
    var reading = AttributeReading()
    reading.names = attributeNames(of: element)
    for name in reading.names {
        guard let value = attribute(element, name) else {
            reading.display.append((name, "no value"))
            continue
        }
        let type = CFGetTypeID(value)
        if type == CFStringGetTypeID() {
            let text = (value as? String) ?? ""
            reading.values[name] = text
            if !text.isEmpty {
                reading.holdsValue.insert(name)
            }
            reading.display.append((name, "string " + shownText(text, title: title, owner: owner)))
        } else if type == CFBooleanGetTypeID() {
            // swiftlint:disable:next force_cast
            let flag = CFBooleanGetValue((value as! CFBoolean))
            reading.values[name] = flag ? "true" : "false"
            reading.holdsValue.insert(name)
            reading.display.append((name, "bool \(flag)"))
        } else if type == CFNumberGetTypeID() {
            reading.values[name] = "\(value)"
            reading.holdsValue.insert(name)
            reading.display.append((name, "number \(value)"))
        } else {
            reading.holdsValue.insert(name)
            let kind: String
            if type == AXUIElementGetTypeID() {
                kind = "element"
            } else if type == AXValueGetTypeID() {
                kind = "AXValue"
            } else if type == CFURLGetTypeID() {
                kind = "url"
            } else if type == CFArrayGetTypeID() {
                kind = "array of \((value as? [CFTypeRef])?.count ?? 0)"
            } else {
                kind = CFCopyTypeIDDescription(type) as String? ?? "other"
            }
            reading.display.append((name, "<" + kind + ">"))
        }
    }
    return reading
}

// MARK: - The Dock

struct DockItem {
    let element: AXUIElement
    let index: Int
    /// What identifies the item between two readings: its bundle identifier, else its position.
    let key: String
    let bundle: String?
    let title: String?
    let reading: AttributeReading
}

struct DockSnapshot {
    var application: AXUIElement
    var applicationChildren: [(role: String, count: Int)] = []
    var list: AXUIElement?
    /// Role and subrole of every child of the list, in the Dock's order.
    var listChildren: [(index: Int, role: String, subrole: String)] = []
    var items = [DockItem]()
}

func runningDock() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first
}

func readDock(pid: pid_t) -> DockSnapshot {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)
    var snapshot = DockSnapshot(application: application)
    let top = children(of: application)
    var counts = [String: Int]()
    for child in top {
        counts[string(child, kAXRoleAttribute) ?? "?", default: 0] += 1
    }
    snapshot.applicationChildren = counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    guard let list = top.first(where: { string($0, kAXRoleAttribute) == kAXListRole }) else {
        return snapshot
    }
    snapshot.list = list
    var usedKeys = Set<String>()
    for (index, child) in children(of: list).enumerated() {
        let role = string(child, kAXRoleAttribute) ?? "?"
        let subrole = string(child, kAXSubroleAttribute) ?? "-"
        snapshot.listChildren.append((index, role, subrole))
        guard subrole == kAXApplicationDockItemSubrole else {
            continue
        }
        let title = string(child, kAXTitleAttribute)
        let bundle = bundleIdentifier(ofURLIn: child)
        var key = bundle ?? "item\(index)"
        if usedKeys.contains(key) {
            key += "#\(index)"
        }
        usedKeys.insert(key)
        snapshot.items.append(DockItem(
            element: child,
            index: index,
            key: key,
            bundle: bundle,
            title: title,
            reading: readAttributes(of: child, title: title, owner: bundle)
        ))
    }
    return snapshot
}

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return "?"
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
        return "?"
    }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func printHeader(_ dock: NSRunningApplication) {
    out("dock-badges-probe macOS \(ProcessInfo.processInfo.operatingSystemVersionString) build \(sysctlString("kern.osversion")) model \(sysctlString("hw.model"))")
    out("dock-badges-probe dock pid \(dock.processIdentifier)")
}

func printSnapshot(_ snapshot: DockSnapshot) {
    out("DOCK: application children: " + snapshot.applicationChildren.map { "\($0.role) x\($0.count)" }.joined(separator: ", "))
    guard snapshot.list != nil else {
        out("  no child with the list role was found")
        return
    }
    out("LIST: \(snapshot.listChildren.count) children")
    let itemsByIndex = Dictionary(snapshot.items.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
    for child in snapshot.listChildren {
        guard let item = itemsByIndex[child.index] else {
            out("  #\(child.index) \(child.role)/\(child.subrole)")
            continue
        }
        out("  #\(child.index) \(child.role)/\(child.subrole) title=\(shownTitle(item.title, owner: item.bundle)) bundle=\(shownKey(item.bundle ?? "-"))")
        for entry in item.reading.display {
            out("      \(entry.name) = \(entry.text)")
        }
    }
}

func printSummary(_ snapshot: DockSnapshot, label: String) {
    out("dock-badges-probe \(label) items=\(snapshot.items.count)")
    var have = [String: Int]()
    var holding = [String: Int]()
    for item in snapshot.items {
        for name in item.reading.names {
            have[name, default: 0] += 1
        }
        for name in item.reading.holdsValue {
            holding[name, default: 0] += 1
        }
    }
    for name in have.keys.sorted() {
        out("dock-badges-probe \(label) attribute \(name) on=\(have[name] ?? 0) holdsValue=\(holding[name] ?? 0)")
    }
}

// MARK: - Watching

let watchedNotifications = [
    kAXValueChangedNotification, kAXTitleChangedNotification, kAXCreatedNotification,
    kAXUIElementDestroyedNotification, kAXLayoutChangedNotification, kAXSelectedChildrenChangedNotification,
]

nonisolated(unsafe) var observer: AXObserver?
nonisolated(unsafe) var observedPid: pid_t = 0
/// The key of every application item that is registered, to say which item a notification came from.
nonisolated(unsafe) var elementKeys = [AXUIElement: String]()
/// What each item's values were when they were last read, by a snapshot or a notification.
nonisolated(unsafe) var tracked = [String: [String: String]]()
nonisolated(unsafe) var notificationCounts = [String: Int]()
nonisolated(unsafe) var registrationOutcomes = [String: (ok: Int, failed: Int)]()
nonisolated(unsafe) var registrationFailuresPrinted = 0
nonisolated(unsafe) var relaunches = 0
nonisolated(unsafe) var reattachGeneration = 0

nonisolated(unsafe) let observerCallback: AXObserverCallback = { _, element, notification, _ in
    handleEvent(element: element, notification: notification as String)
}

func errorName(_ error: AXError) -> String {
    switch error {
    case .success: "success"
    case .failure: "failure"
    case .illegalArgument: "illegalArgument"
    case .invalidUIElement: "invalidUIElement"
    case .invalidUIElementObserver: "invalidUIElementObserver"
    case .cannotComplete: "cannotComplete"
    case .attributeUnsupported: "attributeUnsupported"
    case .actionUnsupported: "actionUnsupported"
    case .notificationUnsupported: "notificationUnsupported"
    case .notImplemented: "notImplemented"
    case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
    case .notificationNotRegistered: "notificationNotRegistered"
    case .apiDisabled: "apiDisabled"
    case .noValue: "noValue"
    case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: "notEnoughPrecision"
    @unknown default: "unknown"
    }
}

func removeObserver() {
    if let observer {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    observer = nil
    elementKeys.removeAll()
    tracked.removeAll()
}

/// Registers every notification on the Dock, its list and each application item, and remembers
/// the values the snapshot read.
func register(_ snapshot: DockSnapshot, pid: pid_t) {
    removeObserver()
    var created: AXObserver?
    guard AXObserverCreate(pid, observerCallback, &created) == .success, let created else {
        out("\(elapsed()) dock-badges-probe observer could not be created for pid \(pid)")
        return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    observer = created
    observedPid = pid
    var targets: [(label: String, element: AXUIElement)] = [("application", snapshot.application)]
    if let list = snapshot.list {
        targets.append(("list", list))
    }
    for item in snapshot.items {
        targets.append(("item " + shownKey(item.key), item.element))
        elementKeys[item.element] = item.key
        tracked[item.key] = item.reading.values
    }
    for target in targets {
        for name in watchedNotifications {
            let result = AXObserverAddNotification(created, target.element, name as CFString, nil)
            let kind = target.label.hasPrefix("item") ? "item" : target.label
            var outcome = registrationOutcomes["\(kind) \(name)"] ?? (0, 0)
            if result == .success {
                outcome.ok += 1
            } else {
                outcome.failed += 1
                if registrationFailuresPrinted < maxRegistrationFailuresPrinted {
                    registrationFailuresPrinted += 1
                    out("  registration failed: \(name) on \(target.label): \(errorName(result)) (\(result.rawValue))")
                }
            }
            registrationOutcomes["\(kind) \(name)"] = outcome
        }
    }
    out("\(elapsed()) registered on \(targets.count) elements (application, list and \(snapshot.items.count) items)")
}

func handleEvent(element: AXUIElement, notification: String) {
    notificationCounts[notification, default: 0] += 1
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
    let role = string(element, kAXRoleAttribute) ?? "?"
    let subrole = string(element, kAXSubroleAttribute) ?? "-"
    let key = elementKeys[element]
    let owner = key.flatMap { isApple($0) ? $0 : nil }
    let title = string(element, kAXTitleAttribute)
    out("\(elapsed()) EVENT \(notification) \(role)/\(subrole) title=\(shownTitle(title, owner: owner)) item=\(key.map(shownKey) ?? "-")")
    guard let key, notification != kAXUIElementDestroyedNotification else {
        return
    }
    let reading = readAttributes(of: element, title: title, owner: key)
    guard !reading.names.isEmpty else {
        out("      (no longer readable)")
        return
    }
    let old = tracked[key] ?? [:]
    for name in Set(old.keys).union(reading.values.keys).sorted() where old[name] != reading.values[name] {
        let before = old[name].map { shownText($0, title: title, owner: key) } ?? "none"
        let after = reading.values[name].map { shownText($0, title: title, owner: key) } ?? "none"
        out("      changed \(name): \(before) -> \(after)")
    }
    tracked[key] = reading.values
}

/// Registers again on the Dock that has just started: its Accessibility tree is not ready at once,
/// so it tries up to ten times, half a second apart.
func reattach(pid: pid_t, generation: Int, attempt: Int) {
    guard generation == reattachGeneration else {
        return
    }
    let snapshot = readDock(pid: pid)
    if snapshot.list != nil {
        out("\(elapsed()) dock-badges-probe relaunch: found the new Dock after \(attempt) attempt(s), \(snapshot.items.count) application items")
        register(snapshot, pid: pid)
        return
    }
    guard attempt < 10 else {
        out("\(elapsed()) dock-badges-probe relaunch: no list after \(attempt) attempts, giving up")
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        reattach(pid: pid, generation: generation, attempt: attempt + 1)
    }
}

func followDockLifecycle() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { notification in
        let quit = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard quit?.bundleIdentifier == dockBundleID else {
            return
        }
        out("\(elapsed()) dock-badges-probe the Dock quit: dropping every element")
        reattachGeneration += 1
        removeObserver()
    }
    center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { notification in
        let launched = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let launched, launched.bundleIdentifier == dockBundleID else {
            return
        }
        relaunches += 1
        reattachGeneration += 1
        out("\(elapsed()) dock-badges-probe the Dock launched again (pid \(observedPid) -> \(launched.processIdentifier))")
        removeObserver()
        reattach(pid: launched.processIdentifier, generation: reattachGeneration, attempt: 1)
    }
}

func watch(seconds: Double, first: DockSnapshot, pid: pid_t) {
    out("")
    out("WATCH: \(seconds) s. Let a message arrive and read another one; run `killall Dock` once.")
    followDockLifecycle()
    register(first, pid: pid)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    out("")
    out("dock-badges-probe watch seconds=\(seconds) notifications=\(notificationCounts.values.reduce(0, +)) relaunches=\(relaunches)")
    for name in notificationCounts.keys.sorted() {
        out("dock-badges-probe notification \(name) count=\(notificationCounts[name] ?? 0)")
    }
    for key in registrationOutcomes.keys.sorted() {
        let outcome = registrationOutcomes[key] ?? (0, 0)
        out("dock-badges-probe registration \(key) ok=\(outcome.ok) failed=\(outcome.failed)")
    }
    guard let current = runningDock() else {
        out("dock-badges-probe the Dock is not running at the end")
        return
    }
    let last = readDock(pid: current.processIdentifier)
    printSummary(last, label: "final")
    var silent = [String]()
    var appeared = 0
    for item in last.items {
        guard let known = tracked[item.key] else {
            appeared += 1
            continue
        }
        let changed = Set(known.keys).union(item.reading.values.keys).filter { known[$0] != item.reading.values[$0] }
        if !changed.isEmpty {
            silent.append(shownKey(item.key) + " (" + changed.sorted().joined(separator: ", ") + ")")
        }
    }
    let disappeared = tracked.keys.filter { key in !last.items.contains { $0.key == key } }.count
    out("dock-badges-probe changed without a notification: \(silent.count) items" + (silent.isEmpty ? "" : ": " + silent.joined(separator: "; ")))
    out("dock-badges-probe items appeared=\(appeared) disappeared=\(disappeared) created=\(notificationCounts[kAXCreatedNotification] ?? 0) destroyed=\(notificationCounts[kAXUIElementDestroyedNotification] ?? 0)")
}

// MARK: - Main

options = parseOptions()
setvbuf(stdout, nil, _IOLBF, 0)
startUptime = ProcessInfo.processInfo.systemUptime

guard AXIsProcessTrusted() else {
    out("This terminal has no Accessibility permission, so nothing can be read.")
    out("Open System Settings > Privacy & Security > Accessibility, switch on the terminal app you ran this in,")
    out("quit and reopen the terminal, and run the probe again.")
    exit(2)
}
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)

guard let dock = runningDock() else {
    out("The Dock is not running.")
    exit(3)
}
printHeader(dock)
let snapshot = readDock(pid: dock.processIdentifier)
printSnapshot(snapshot)
printSummary(snapshot, label: "first")
if let seconds = options.watch {
    watch(seconds: seconds, first: snapshot, pid: dock.processIdentifier)
}
out("")
out("=== end of report (\(elapsed())) ===")
