// Phase 22 spike: what does macOS 27's native overflow control look like to Accessibility while
// it is collapsed and while it is expanded? Read-only: public Accessibility and CoreGraphics
// calls only, no network, no private API, nothing is clicked, moved or written.
//
// Run it on a notched MacBook on macOS 27, twice:
//
//   swift Scripts/macos27/overflow-state-probe.swift --label collapsed 2>&1 | tee ~/Desktop/overflow-collapsed.txt
//   swift Scripts/macos27/overflow-state-probe.swift --label expanded  2>&1 | tee ~/Desktop/overflow-expanded.txt
//
// The terminal needs Accessibility (System Settings > Privacy & Security > Accessibility).
//
// What a run does:
//   1. BEFORE snapshot: macOS build, displays and the notch, the overflow control's Accessibility
//      attributes and actions, every extras-bar item with its frame, where it sits relative to the
//      control and the notch, and whether a hit test at its centre finds the item.
//   2. Observation window (--seconds, default 20): Accessibility observers listen for every public
//      notification on MenuBarAgent, the control and the items, while the control's own state and
//      the item frames are sampled. Click the overflow control ONCE during the window.
//   3. AFTER snapshot, a diff of the two, and a count of the notifications seen.
//
// Options:
//   --label <text>    what the overflow is when the run starts: collapsed or expanded (free text)
//   --seconds <n>     length of the observation window; 0 takes the snapshot only (default 20)
//   --redact          replace the bundle identifiers, titles and descriptions of non-Apple apps
//   --tree            also print MenuBarAgent's Accessibility tree (printed anyway when no control is found)
//   --help
import AppKit
import ApplicationServices

// MARK: - Options and shared state

struct Options {
    var seconds = 20.0
    var label = "unlabelled"
    var redact = false
    var tree = false
}

nonisolated(unsafe) var options = Options()
nonisolated(unsafe) var startUptime = ProcessInfo.processInfo.systemUptime
nonisolated(unsafe) var bundleAliases = [String: String]()
nonisolated(unsafe) var pidBundles = [pid_t: String]()
nonisolated(unsafe) var eventCounts = [String: Int]()
nonisolated(unsafe) var printedEvents = 0
nonisolated(unsafe) var firstEventAt: Double?
nonisolated(unsafe) var lastEventAt: Double?

let agentBundleID = "com.apple.MenuBarAgent"
let maxPrintedEvents = 300

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--seconds":
            if let value = arguments.first, let seconds = Double(value) {
                parsed.seconds = max(0, seconds)
                arguments.removeFirst()
            }
        case "--label":
            if let value = arguments.first {
                parsed.label = value
                arguments.removeFirst()
            }
        case "--redact":
            parsed.redact = true
        case "--tree":
            parsed.tree = true
        case "--help", "-h":
            print("usage: swift overflow-state-probe.swift [--label collapsed|expanded] [--seconds N] [--redact] [--tree]")
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

func isApple(_ bundleID: String) -> Bool {
    bundleID.hasPrefix("com.apple.")
}

/// The bundle identifier as it is printed: the real one, or `app<n>` for a non-Apple app with --redact
/// (numbered in the order first seen, consistent within one run only).
func shownBundle(_ bundleID: String) -> String {
    guard options.redact, !isApple(bundleID) else {
        return bundleID
    }
    if let alias = bundleAliases[bundleID] {
        return alias
    }
    let alias = "app\(bundleAliases.count + 1)"
    bundleAliases[bundleID] = alias
    return alias
}

func shownText(_ text: String?, owner: String) -> String {
    guard let text else {
        return "-"
    }
    if options.redact, !isApple(owner) {
        return "<redacted>"
    }
    let flat = text.replacingOccurrences(of: "\n", with: "\\n")
    return "\"" + (flat.count > 80 ? String(flat.prefix(80)) + "..." : flat) + "\""
}

func shown(_ rect: CGRect?) -> String {
    guard let rect else {
        return "none"
    }
    return String(format: "(%.1f,%.1f %.1fx%.1f)", rect.minX, rect.minY, rect.width, rect.height)
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

func frame(of element: AXUIElement) -> CGRect? {
    guard
        let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
        let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
    else {
        return nil
    }
    var point = CGPoint.zero
    var extent = CGSize.zero
    // swiftlint:disable:next force_cast
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else {
        return nil
    }
    return CGRect(origin: point, size: extent)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func ownerBundle(of element: AXUIElement) -> String {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    if let known = pidBundles[pid] {
        return known
    }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid\(pid)"
}

/// One line about an element: role/subrole, identifier, description, title.
func brief(_ element: AXUIElement) -> String {
    let owner = ownerBundle(of: element)
    var role = string(element, kAXRoleAttribute) ?? "?"
    if let subrole = string(element, kAXSubroleAttribute) {
        role += "/" + subrole
    }
    var parts = [role]
    if let identifier = string(element, kAXIdentifierAttribute) {
        parts.append("id=" + shownText(identifier, owner: owner))
    }
    if let description = string(element, kAXDescriptionAttribute) {
        parts.append("desc=" + shownText(description, owner: owner))
    }
    if let title = string(element, kAXTitleAttribute) {
        parts.append("title=" + shownText(title, owner: owner))
    }
    return parts.joined(separator: " ")
}

/// Renders an attribute value of any type on one line.
func describe(_ value: CFTypeRef?, owner: String) -> String {
    guard let value else {
        return "nil"
    }
    let type = CFGetTypeID(value)
    if type == AXValueGetTypeID() {
        // swiftlint:disable:next force_cast
        let axValue = value as! AXValue
        switch AXValueGetType(axValue) {
        case .cgPoint:
            var point = CGPoint.zero
            AXValueGetValue(axValue, .cgPoint, &point)
            return String(format: "point(%.1f,%.1f)", point.x, point.y)
        case .cgSize:
            var size = CGSize.zero
            AXValueGetValue(axValue, .cgSize, &size)
            return String(format: "size(%.1fx%.1f)", size.width, size.height)
        case .cgRect:
            var rect = CGRect.zero
            AXValueGetValue(axValue, .cgRect, &rect)
            return "rect" + shown(rect)
        case .cfRange:
            var range = CFRange()
            AXValueGetValue(axValue, .cfRange, &range)
            return "range(\(range.location),\(range.length))"
        default:
            return "AXValue(other)"
        }
    }
    if type == AXUIElementGetTypeID() {
        // swiftlint:disable:next force_cast
        return "<" + brief(value as! AXUIElement) + ">"
    }
    if type == CFStringGetTypeID() {
        return shownText(value as? String, owner: owner)
    }
    if type == CFBooleanGetTypeID() {
        // swiftlint:disable:next force_cast
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    }
    if type == CFNumberGetTypeID() {
        return "\(value)"
    }
    if type == CFArrayGetTypeID() {
        let array = value as? [CFTypeRef] ?? []
        let head = array.prefix(3).map { describe($0, owner: owner) }.joined(separator: ", ")
        return "[\(array.count)]" + (head.isEmpty ? "" : " " + head + (array.count > 3 ? ", ..." : ""))
    }
    if type == CFURLGetTypeID() {
        return "url(<omitted>)"
    }
    return "type(\(CFCopyTypeIDDescription(type) as String? ?? "?"))"
}

func stringArray(_ copy: (UnsafeMutablePointer<CFArray?>) -> AXError) -> [String] {
    var names: CFArray?
    guard copy(&names) == .success else {
        return []
    }
    return names as? [String] ?? []
}

// MARK: - System facts

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return "?"
    }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
        return "?"
    }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
}

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let notch: ClosedRange<CGFloat>?
}

func displays() -> [DisplayInfo] {
    NSScreen.screens.map { screen in
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        var notch: ClosedRange<CGFloat>?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let minX = screen.frame.minX + left.width
            let maxX = screen.frame.maxX - right.width
            notch = minX < maxX ? minX...maxX : nil
        }
        return DisplayInfo(id: number, name: screen.localizedName, frame: CGDisplayBounds(number), notch: notch)
    }
}

func displayID(at point: CGPoint) -> CGDirectDisplayID? {
    var display = CGDirectDisplayID(0)
    var matches: UInt32 = 0
    CGGetDisplaysWithPoint(point, 1, &display, &matches)
    return matches > 0 ? display : nil
}

func printHeader(_ displays: [DisplayInfo]) {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let formatter = ISO8601DateFormatter()
    out("=== holzBar overflow-state-probe v1 ===")
    out("label=\(options.label) redact=\(options.redact) seconds=\(options.seconds) at=\(formatter.string(from: Date()))")
    out("macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) build=\(sysctlString("kern.osversion")) model=\(sysctlString("hw.model"))")
    out("system=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    if version.majorVersion < 27 {
        out("WARNING: this Mac runs macOS \(version.majorVersion), the probe is meant for macOS 27")
    }
    for display in displays {
        let notch = display.notch.map { String(format: "notch x=%.1f...%.1f (width %.1f)", $0.lowerBound, $0.upperBound, $0.upperBound - $0.lowerBound) } ?? "no notch"
        out("display id=\(display.id) \"\(display.name)\" bounds=\(shown(display.frame)) \(notch)")
    }
    let agents = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == agentBundleID }
    out("MenuBarAgent pids=\(agents.map { String($0.processIdentifier) }.joined(separator: ","))")
}

// MARK: - Finding the control and the items

func agentApplication() -> (app: AXUIElement, pid: pid_t)? {
    guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == agentBundleID }) else {
        return nil
    }
    let application = AXUIElementCreateApplication(agent.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 1.0)
    return (application, agent.processIdentifier)
}

func extrasBar(of application: AXUIElement) -> AXUIElement? {
    guard let bar = attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
        return nil
    }
    // swiftlint:disable:next force_cast
    return (bar as! AXUIElement)
}

/// The system overflow control the way holzBar finds it: the child of MenuBarAgent's extras bar
/// with role AXButton.
func findControl() -> (element: AXUIElement, index: Int, bar: AXUIElement)? {
    guard let agent = agentApplication(), let bar = extrasBar(of: agent.app) else {
        return nil
    }
    for (index, child) in children(of: bar).enumerated() where string(child, kAXRoleAttribute) == kAXButtonRole {
        return (child, index, bar)
    }
    return nil
}

struct Item {
    let bundleID: String
    let pid: pid_t
    let index: Int
    let element: AXUIElement
    let role: String
    let identifier: String?
    let text: String?
    let frame: CGRect?
    var key: String { "\(bundleID)|\(identifier ?? "")|\(index)" }
}

/// Every extras-bar item of every running process. MenuBarAgent's items are the hosting groups'
/// inner elements (as in MenuBarItemProvider27); its AXButton child is left out, it is the control.
func scanItems() -> [Item] {
    var items = [Item]()
    let running = NSWorkspace.shared.runningApplications
    let ordered = running.filter { $0.bundleIdentifier == agentBundleID } + running.filter { $0.bundleIdentifier != agentBundleID }
    for app in ordered {
        guard let bundleID = app.bundleIdentifier else {
            continue
        }
        pidBundles[app.processIdentifier] = bundleID
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, bundleID == agentBundleID ? 1.0 : 0.4)
        guard let bar = extrasBar(of: application) else {
            continue
        }
        for (index, child) in children(of: bar).enumerated() {
            if bundleID == agentBundleID, string(child, kAXRoleAttribute) == kAXButtonRole {
                continue
            }
            let element = bundleID == agentBundleID ? (children(of: child).first ?? child) : child
            items.append(Item(
                bundleID: bundleID,
                pid: app.processIdentifier,
                index: index,
                element: element,
                role: string(element, kAXRoleAttribute) ?? "?",
                identifier: string(element, kAXIdentifierAttribute),
                text: string(element, kAXDescriptionAttribute) ?? string(element, kAXTitleAttribute),
                frame: frame(of: element)
            ))
        }
    }
    return items
}

/// What the control looks like right now, on one line, for change detection.
func controlSignature() -> String {
    guard let control = findControl() else {
        return "absent"
    }
    let element = control.element
    return [
        "present", "frame=" + shown(frame(of: element)),
        "title=" + shownText(string(element, kAXTitleAttribute), owner: agentBundleID),
        "desc=" + shownText(string(element, kAXDescriptionAttribute), owner: agentBundleID),
        "value=" + describe(attribute(element, kAXValueAttribute), owner: agentBundleID),
        "id=" + shownText(string(element, kAXIdentifierAttribute), owner: agentBundleID),
    ].joined(separator: " ")
}

func itemsSignature(_ items: [Item]) -> String {
    items.map { "\($0.key)@\(shown($0.frame))" }.joined(separator: ";")
}

func hitTest(_ rect: CGRect, systemWide: AXUIElement) -> AXUIElement? {
    var hit: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWide, Float(rect.midX), Float(rect.midY), &hit)
    return result == .success ? hit : nil
}

// MARK: - Snapshot

struct Snapshot {
    var controlAttributes: [String: String]?
    var controlFrame: CGRect?
    var items: [Item]
}

func printAXTree(_ element: AXUIElement, depth: Int, budget: inout Int) {
    guard depth <= 6, budget > 0 else {
        return
    }
    budget -= 1
    out(String(repeating: "  ", count: depth + 1) + brief(element) + " frame=" + shown(frame(of: element)))
    for child in children(of: element) {
        printAXTree(child, depth: depth + 1, budget: &budget)
    }
}

/// Elements that could be an overflow control: by role or by a telling title or description.
func candidates(in root: AXUIElement, depth: Int, found: inout [String], budget: inout Int) {
    guard depth <= 6, budget > 0, found.count < 40 else {
        return
    }
    budget -= 1
    let role = string(root, kAXRoleAttribute) ?? ""
    let text = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute]
        .compactMap { string(root, $0) }.joined(separator: " ").lowercased()
    let words = ["overflow", "more", "expand", "collapse", "chevron", "<<", ">>", "\u{00AB}", "\u{00BB}", "\u{2039}", "\u{203A}"]
    let buttonRoles: Set<String> = [kAXButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXDisclosureTriangleRole, kAXCheckBoxRole]
    if buttonRoles.contains(role) || words.contains(where: text.contains) {
        found.append("depth=\(depth) " + brief(root) + " frame=" + shown(frame(of: root)))
    }
    for child in children(of: root) {
        candidates(in: child, depth: depth + 1, found: &found, budget: &budget)
    }
}

func takeSnapshot(_ name: String, displays: [DisplayInfo]) -> Snapshot {
    out("")
    out("--- SNAPSHOT \(name) (\(elapsed())) ---")
    let systemWide = AXUIElementCreateSystemWide()
    let control = findControl()
    var attributes: [String: String]?
    var controlFrame: CGRect?

    // The control.
    if let control {
        let element = control.element
        controlFrame = frame(of: element)
        out("CONTROL found as child #\(control.index) of MenuBarAgent's AXExtrasMenuBar, frame=\(shown(controlFrame))")
        var dump = [String: String]()
        for name in stringArray({ AXUIElementCopyAttributeNames(element, $0) }).sorted() {
            dump[name] = describe(attribute(element, name), owner: agentBundleID)
        }
        attributes = dump
        for name in dump.keys.sorted() {
            out("  attr \(name) = \(dump[name] ?? "")")
        }
        let parameterized = stringArray { AXUIElementCopyParameterizedAttributeNames(element, $0) }
        out("  parameterized attributes: \(parameterized.isEmpty ? "none" : parameterized.joined(separator: ", "))")
        let actions = stringArray { AXUIElementCopyActionNames(element, $0) }
        if actions.isEmpty {
            out("  actions: none")
        }
        for action in actions {
            var description: CFString?
            AXUIElementCopyActionDescription(element, action as CFString, &description)
            out("  action \(action) = \((description as String?).map { shownText($0, owner: agentBundleID) } ?? "-")")
        }
        for name in [kAXValueAttribute, kAXEnabledAttribute, kAXFocusedAttribute] {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success {
                out("  settable \(name) = \(settable.boolValue)")
            }
        }
        out("  hit test at the centre: " + hitDescription(controlFrame, expecting: element, systemWide: systemWide))
    } else {
        out("CONTROL not found: MenuBarAgent's AXExtrasMenuBar has no AXButton child")
    }

    // MenuBarAgent's extras bar children, the control included.
    if let agent = agentApplication(), let bar = extrasBar(of: agent.app) {
        let kids = children(of: bar)
        out("MenuBarAgent extras bar: \(kids.count) children")
        for (index, kid) in kids.enumerated() {
            out("  #\(index) \(brief(kid)) frame=\(shown(frame(of: kid)))")
        }
        let windows = (attribute(agent.app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        out("MenuBarAgent AX windows: \(windows.count)")
        for window in windows {
            out("  \(brief(window)) frame=\(shown(frame(of: window))) children=\(children(of: window).count)")
        }
        if control == nil || options.tree {
            out("MenuBarAgent AX tree (depth 6, at most 400 elements):")
            var budget = 400
            printAXTree(agent.app, depth: 0, budget: &budget)
            var found = [String]()
            var searchBudget = 400
            candidates(in: agent.app, depth: 0, found: &found, budget: &searchBudget)
            out("control candidates by role or text (\(found.count)):")
            for line in found {
                out("  " + line)
            }
        }
    } else {
        out("MenuBarAgent: no extras bar (process not running, or Accessibility denied)")
    }
    printAgentWindows()

    // The items.
    let items = scanItems()
    printItems(items, control: controlFrame, displays: displays, systemWide: systemWide)
    return Snapshot(controlAttributes: attributes, controlFrame: controlFrame, items: items)
}

func hitDescription(_ rect: CGRect?, expecting element: AXUIElement, systemWide: AXUIElement) -> String {
    guard let rect, rect.width > 0, rect.height > 0 else {
        return "n/a"
    }
    guard let hit = hitTest(rect, systemWide: systemWide) else {
        return "none"
    }
    if CFEqual(hit, element) {
        return "self"
    }
    return "other(" + shownBundle(ownerBundle(of: hit)) + " " + (string(hit, kAXRoleAttribute) ?? "?") + ")"
}

/// MenuBarAgent's windows from the window list (public, no screen recording needed for bounds).
func printAgentWindows() {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "MenuBarAgent" }
    out("MenuBarAgent windows in the window list: \(mine.count)")
    for window in mine.prefix(12) {
        let bounds = (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let layer = window[kCGWindowLayer as String] as? Int ?? -1
        let alpha = window[kCGWindowAlpha as String] as? Double ?? -1
        let onscreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
        out("  layer=\(layer) alpha=\(alpha) onscreen=\(onscreen) bounds=\(shown(bounds))")
    }
}

struct ItemFacts {
    var withFrame = 0
    var noFrame = 0
    var zeroSize = 0
    var atOrigin = 0
    var overlapControl = 0
    var underNotch = 0
    var leftOfNotch = 0
    var rightOfNotch = 0
    var stackedPairs = 0
    var hitConfirms = 0
}

func printItems(_ items: [Item], control: CGRect?, displays: [DisplayInfo], systemWide: AXUIElement) {
    out("ITEMS: \(items.count) extras-bar items from all running processes, sorted by x")
    out("  flags: C overlaps the control (holzBar's folded test), N under the notch, L left of it, R right of it; hit: does the element at its centre equal the item")
    var facts = ItemFacts()
    let sorted = items.sorted { ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude) }
    var previous: [CGDirectDisplayID: CGRect] = [:]
    for item in sorted {
        let owner = item.bundleID
        guard let rect = item.frame else {
            facts.noFrame += 1
            out("  NO-FRAME \(shownBundle(owner)) #\(item.index) \(item.role) id=\(shownText(item.identifier, owner: owner)) text=\(shownText(item.text, owner: owner))")
            continue
        }
        facts.withFrame += 1
        var flags = ""
        if rect.width <= 0 || rect.height <= 0 {
            facts.zeroSize += 1
            flags += "Z"
        }
        if rect.minX == 0, rect.minY == 0 {
            facts.atOrigin += 1
            flags += "O"
        }
        if let control, rect.maxX > control.minX, rect.minX < control.maxX {
            facts.overlapControl += 1
            flags += "C"
        }
        let display = displayID(at: CGPoint(x: rect.midX, y: rect.midY))
        let notch = displays.first { $0.id == display }?.notch
        if let notch {
            let tolerance: CGFloat = 6
            if rect.maxX - tolerance > notch.lowerBound, rect.minX + tolerance < notch.upperBound {
                facts.underNotch += 1
                flags += "N"
            } else if rect.maxX <= notch.lowerBound + tolerance {
                facts.leftOfNotch += 1
                flags += "L"
            } else {
                facts.rightOfNotch += 1
                flags += "R"
            }
        }
        if rect.width > 4, let display {
            if let last = previous[display], last.maxX - rect.minX > 6 {
                facts.stackedPairs += 1
            }
            previous[display] = rect
        }
        let hit = hitDescription(rect, expecting: item.element, systemWide: systemWide)
        if hit == "self" {
            facts.hitConfirms += 1
        }
        out(String(format: "  x=%8.1f y=%5.1f w=%6.1f h=%5.1f d=%@ [%@] hit=%@ ", rect.minX, rect.minY, rect.width, rect.height, display.map { "\($0)" } ?? "-", flags, hit)
            + "\(shownBundle(owner)) #\(item.index) \(item.role) id=\(shownText(item.identifier, owner: owner)) text=\(shownText(item.text, owner: owner))")
    }
    out("FACTS items=\(items.count) withFrame=\(facts.withFrame) noFrame=\(facts.noFrame) zeroSize=\(facts.zeroSize) atOrigin=\(facts.atOrigin) "
        + "overlapControl=\(facts.overlapControl) underNotch=\(facts.underNotch) leftOfNotch=\(facts.leftOfNotch) rightOfNotch=\(facts.rightOfNotch) "
        + "stackedPairs=\(facts.stackedPairs) hitConfirms=\(facts.hitConfirms) controlFrame=\(shown(control))")
}

// MARK: - Observation

nonisolated(unsafe) let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    let pid = refcon.map { pid_t(truncatingIfNeeded: Int(bitPattern: $0)) } ?? 0
    handleEvent(element: element, notification: notification as String, pid: pid)
}

func handleEvent(element: AXUIElement, notification: String, pid: pid_t) {
    let now = ProcessInfo.processInfo.systemUptime - startUptime
    firstEventAt = firstEventAt ?? now
    lastEventAt = now
    let owner = pidBundles[pid] ?? "pid\(pid)"
    eventCounts["\(shownBundle(owner)) \(notification)", default: 0] += 1
    guard printedEvents < maxPrintedEvents else {
        return
    }
    printedEvents += 1
    AXUIElementSetMessagingTimeout(element, 0.3)
    out("\(elapsed()) EVENT \(notification) from \(shownBundle(owner)): \(brief(element)) frame=\(shown(frame(of: element)))")
}

let allNotifications = [
    "AXMoved", "AXResized", "AXCreated", "AXUIElementDestroyed", "AXValueChanged", "AXTitleChanged", "AXLayoutChanged",
    "AXSelectedChildrenChanged", "AXSelectedChildrenMoved", "AXWindowCreated", "AXWindowMoved", "AXWindowResized",
    "AXFocusedUIElementChanged", "AXFocusedWindowChanged", "AXMainWindowChanged", "AXApplicationShown", "AXApplicationHidden",
    "AXApplicationActivated", "AXApplicationDeactivated", "AXMenuOpened", "AXMenuClosed", "AXMenuItemSelected",
    "AXRowCountChanged", "AXElementBusyChanged", "AXAnnouncementRequested", "AXSelectedChildrenChanged", "AXUIElementsChanged",
]
let itemNotifications = ["AXMoved", "AXResized", "AXCreated", "AXUIElementDestroyed", "AXValueChanged", "AXTitleChanged", "AXLayoutChanged"]

/// Registers observers and returns them (kept alive by the caller). Prints which notifications
/// the control accepts: those are the ones it can post.
func startObserving(control: (element: AXUIElement, index: Int, bar: AXUIElement)?, items: [Item]) -> [AXObserver] {
    var observers = [pid_t: AXObserver]()
    func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] {
            return existing
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &created) == .success, let created else {
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observers[pid] = created
        return created
    }
    func register(_ element: AXUIElement, pid: pid_t, notifications: [String]) -> [String: AXError] {
        guard let observer = observer(for: pid) else {
            return [:]
        }
        var results = [String: AXError]()
        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        for notification in Set(notifications) {
            results[notification] = AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        return results
    }

    if let agent = agentApplication() {
        pidBundles[agent.pid] = agentBundleID
        var targets: [(String, AXUIElement)] = [("application", agent.app)]
        for window in (attribute(agent.app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            targets.append(("window", window))
        }
        if let bar = extrasBar(of: agent.app) {
            targets.append(("extras bar", bar))
            for kid in children(of: bar) {
                targets.append(("extras bar child", kid))
            }
        }
        var accepted = [String: Set<String>]()
        for (label, element) in targets {
            for (notification, result) in register(element, pid: agent.pid, notifications: allNotifications) where result == .success || result == .notificationAlreadyRegistered {
                accepted[label, default: []].insert(notification)
            }
        }
        for (label, _) in targets {
            // one line per kind of target
            if let names = accepted.removeValue(forKey: label) {
                out("OBSERVING MenuBarAgent \(label): accepted \(names.sorted().joined(separator: ", "))")
            }
        }
        if let control {
            let results = register(control.element, pid: agent.pid, notifications: allNotifications)
            let accepted = results.filter { $0.value == .success || $0.value == .notificationAlreadyRegistered }.keys.sorted()
            let refused = results.filter { $0.value != .success && $0.value != .notificationAlreadyRegistered }
                .map { "\($0.key)=\($0.value.rawValue)" }.sorted()
            out("OBSERVING the control itself: accepted \(accepted.joined(separator: ", "))")
            out("  refused (AXError raw value): \(refused.joined(separator: ", "))")
        }
    }
    var watched = 0
    for pid in Set(items.map(\.pid)) where pid != agentApplication()?.pid {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        _ = register(application, pid: pid, notifications: ["AXCreated", "AXUIElementDestroyed", "AXLayoutChanged"])
        for item in items where item.pid == pid {
            if register(item.element, pid: pid, notifications: itemNotifications).values.contains(.success) {
                watched += 1
            }
        }
    }
    out("OBSERVING \(watched) items of other apps (moved, resized, created, destroyed, value, title, layout)")
    return Array(observers.values)
}

/// Runs the run loop for the window, sampling the control every 0.25 s and the item frames every second.
func observe(seconds: Double, control: (element: AXUIElement, index: Int, bar: AXUIElement)?, items: [Item]) {
    out("")
    out("--- OBSERVING for \(seconds) s (\(elapsed())) ---")
    let observers = startObserving(control: control, items: items)
    out(">>> NOW: click the overflow control ONCE (\(options.label) -> toggled). Leave the pointer alone afterwards. <<<")
    let begin = ProcessInfo.processInfo.systemUptime
    var lastControl = controlSignature()
    var lastItems = itemsSignature(items)
    var lastControlPoll = begin
    var lastScan = begin
    var warned = false
    out("\(elapsed()) POLL control: \(lastControl)")
    while ProcessInfo.processInfo.systemUptime - begin < seconds {
        CFRunLoopRunInMode(.defaultMode, 0.1, false)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastControlPoll >= 0.25 {
            lastControlPoll = now
            let signature = controlSignature()
            if signature != lastControl {
                out("\(elapsed()) POLL control changed: \(signature)")
                lastControl = signature
            }
        }
        if now - lastScan >= 1.0 {
            lastScan = now
            let signature = itemsSignature(scanItems())
            if signature != lastItems {
                out("\(elapsed()) POLL item frames changed")
                lastItems = signature
            }
        }
        if !warned, seconds - (now - begin) < 5 {
            warned = true
            out("\(elapsed()) (5 s left)")
        }
    }
    withExtendedLifetime(observers) {}
    out("--- OBSERVATION ENDED (\(elapsed())) ---")
    out("EVENTS seen: \(eventCounts.values.reduce(0, +)) (printed \(printedEvents)); first at \(firstEventAt.map { String(format: "t+%.2fs", $0) } ?? "none"), last at \(lastEventAt.map { String(format: "t+%.2fs", $0) } ?? "none")")
    for (name, count) in eventCounts.sorted(by: { $0.value > $1.value }).prefix(40) {
        out("  \(count)x \(name)")
    }
}

// MARK: - Comparison

func printDiff(before: Snapshot, after: Snapshot) {
    out("")
    out("--- DIFF before -> after ---")
    switch (before.controlAttributes, after.controlAttributes) {
    case let (old?, new?):
        var changed = 0
        for name in Set(old.keys).union(new.keys).sorted() where old[name] != new[name] {
            changed += 1
            out("  control attr \(name): \(old[name] ?? "absent") -> \(new[name] ?? "absent")")
        }
        if changed == 0 {
            out("  control attributes: identical")
        }
    case (nil, nil):
        out("  control: absent in both snapshots")
    case (let old, let new):
        out("  control: \(old == nil ? "absent" : "present") -> \(new == nil ? "absent" : "present")")
    }
    out("  control frame: \(shown(before.controlFrame)) -> \(shown(after.controlFrame))")
    let old = Dictionary(before.items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    let new = Dictionary(after.items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    out("  items: \(before.items.count) -> \(after.items.count); appeared \(new.keys.filter { old[$0] == nil }.count), disappeared \(old.keys.filter { new[$0] == nil }.count)")
    var moved = 0
    for key in old.keys.sorted() {
        guard let first = old[key], let second = new[key], first.frame != second.frame else {
            continue
        }
        moved += 1
        if moved <= 40 {
            out("  moved \(shownBundle(first.bundleID)) #\(first.index): \(shown(first.frame)) -> \(shown(second.frame))")
        }
    }
    out("  items whose frame changed: \(moved)")
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
// Every Accessibility call waits at most this long, unless an element sets its own.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

let screens = displays()
printHeader(screens)
let before = takeSnapshot("BEFORE", displays: screens)
if options.seconds > 0 {
    observe(seconds: options.seconds, control: findControl(), items: before.items)
    let after = takeSnapshot("AFTER", displays: screens)
    printDiff(before: before, after: after)
}
out("")
out("=== end of report (\(elapsed())) ===")
