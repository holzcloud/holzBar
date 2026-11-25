// P4 probe of phase 93: what does a Live Activity in the macOS 27.3 menu bar look like to
// Accessibility? holzBar recognises Live Activities only through the Accessibility discovery it
// already runs, so this prints what MenuBarAgent exposes while one is on the bar. Read-only:
// public Accessibility and CoreGraphics calls only, no network, no private API, nothing is
// clicked, moved or written, and it starts no process.
//
// Run it on a Mac on macOS 27.3, once for each case (the label is free text that is printed):
//
//   swift Scripts/macos27/live-activity-probe.swift --label clock-timer 2>&1 | tee ~/Desktop/P4-live-clock-timer.txt
//
// Labels used by the runbook: none (no Live Activity), clock-timer, voice-memos, screen-recording,
// music. Run it once more while holzBar hides an app.
//
// The terminal needs Accessibility (System Settings > Privacy & Security > Accessibility); the
// probe exits with status 2 and one line when it is not granted.
//
// It prints the macOS build; then, for MenuBarAgent, every child of its extras menu bar and, for
// hosting groups, the first child inside (role, subrole, identifier, description, title, frame),
// and the children of each of its windows the same way; then every on-screen window of
// MenuBarAgent, Control Centre and the notification centre from CGWindowListCopyWindowInfo (layer,
// bounds, alpha); then, for every other running application, the identifiers and frames of its
// extras-bar items.
//
// Options:
//   --label <text>   what is on the bar during this run (default unlabelled)
//   --redact         print "other" instead of non-Apple bundle identifiers, and hide their texts
//   --help
import AppKit
import ApplicationServices

struct Options {
    var label = "unlabelled"
    var redact = false
}

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--label":
            if let value = arguments.first {
                parsed.label = value
                arguments.removeFirst()
            }
        case "--redact":
            parsed.redact = true
        case "--help", "-h":
            print("usage: swift live-activity-probe.swift [--label TEXT] [--redact]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
    return parsed
}

let options = parseOptions()
let agentBundleID = "com.apple.MenuBarAgent"

func isApple(_ bundleID: String) -> Bool {
    bundleID.hasPrefix("com.apple.")
}

func shownBundle(_ bundleID: String) -> String {
    options.redact && !isApple(bundleID) ? "other" : bundleID
}

func shownText(_ text: String?, owner: String) -> String {
    guard let text else { return "-" }
    if options.redact && !isApple(owner) { return "<redacted>" }
    let flat = text.replacingOccurrences(of: "\n", with: "\\n")
    return "\"" + (flat.count > 80 ? String(flat.prefix(80)) + "..." : flat) + "\""
}

func shown(_ rect: CGRect?) -> String {
    guard let rect else { return "none" }
    return String(format: "(%.1f,%.1f %.1fx%.1f)", rect.minX, rect.minY, rect.width, rect.height)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name), CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
    let text = value as? String
    return text?.isEmpty == false ? text : nil
}

func frame(of element: AXUIElement) -> CGRect? {
    guard
        let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
        let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
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

func brief(_ element: AXUIElement, owner: String) -> String {
    var role = string(element, kAXRoleAttribute) ?? "?"
    if let subrole = string(element, kAXSubroleAttribute) { role += "/" + subrole }
    var parts = [role]
    if let identifier = string(element, kAXIdentifierAttribute) { parts.append("id=" + shownText(identifier, owner: owner)) }
    if let description = string(element, kAXDescriptionAttribute) { parts.append("desc=" + shownText(description, owner: owner)) }
    if let title = string(element, kAXTitleAttribute) { parts.append("title=" + shownText(title, owner: owner)) }
    parts.append(shown(frame(of: element)))
    return parts.joined(separator: " ")
}

func printChildren(of element: AXUIElement, owner: String, indent: String) {
    for (index, child) in children(of: element).enumerated() {
        print("\(indent)[\(index)] \(brief(child, owner: owner))")
        if string(child, kAXRoleAttribute) == kAXGroupRole {
            if let first = children(of: child).first {
                print("\(indent)    first child: \(brief(first, owner: owner))")
            }
        }
    }
}

guard AXIsProcessTrusted() else {
    print("Accessibility is not granted to this terminal: System Settings > Privacy & Security > Accessibility")
    exit(2)
}

print("label: \(options.label)")
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

if let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first {
    let application = AXUIElementCreateApplication(agent.processIdentifier)
    print("")
    print("\(agentBundleID) extras menu bar:")
    if let extras = attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() {
        // swiftlint:disable:next force_cast
        printChildren(of: extras as! AXUIElement, owner: agentBundleID, indent: "  ")
    } else {
        print("  no extras menu bar")
    }
    print("\(agentBundleID) windows:")
    let windows = (attribute(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    for (index, window) in windows.enumerated() {
        print("  window [\(index)] \(brief(window, owner: agentBundleID))")
        printChildren(of: window, owner: agentBundleID, indent: "    ")
    }
    if windows.isEmpty { print("  none") }
} else {
    print("\(agentBundleID): not running")
}

print("")
print("on-screen windows of the system's menu bar processes:")
let watched: Set<String> = [agentBundleID, "com.apple.controlcenter", "com.apple.notificationcenterui"]
if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
    for entry in list {
        guard let owner = entry[kCGWindowOwnerPID as String] as? Int32,
              let bundleID = NSRunningApplication(processIdentifier: owner)?.bundleIdentifier,
              watched.contains(bundleID),
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { continue }
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
        print("  \(bundleID) layer \(layer) \(shown(bounds)) alpha \(String(format: "%.2f", alpha))")
    }
}

print("")
print("extras-bar items of other applications:")
for application in NSWorkspace.shared.runningApplications where application.bundleIdentifier != agentBundleID {
    let bundleID = application.bundleIdentifier ?? "pid\(application.processIdentifier)"
    let element = AXUIElementCreateApplication(application.processIdentifier)
    guard let extras = attribute(element, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
    // swiftlint:disable:next force_cast
    let items = children(of: extras as! AXUIElement)
    guard !items.isEmpty else { continue }
    print("  \(shownBundle(bundleID)):")
    for item in items {
        print("    \(brief(item, owner: bundleID))")
    }
}
