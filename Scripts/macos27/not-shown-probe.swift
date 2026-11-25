// Which menu bar items does macOS not show? Two read-only questions, answered from what the
// running apps publish through Accessibility. Read-only: public Accessibility attribute reads with
// a short messaging timeout and AppKit/CoreGraphics geometry only. It sets no attribute, performs
// no action, posts no event, starts no process and opens no connection.
//
// Run it on macOS 27 with the terminal allowed in Accessibility (System Settings > Privacy &
// Security > Accessibility):
//
//   swift Scripts/macos27/not-shown-probe.swift 2>&1 | tee ~/Desktop/not-shown.txt
//
// Part A: apps without a bundle identifier. Every running application whose bundle identifier is
//   missing is asked for its extras bar (a 0.25 s limit); the process identifier, name and
//   executable path are printed and, if its extras bar has children, it is listed as an owner of
//   menu bar items.
// Part B: items that are published but not drawn. Per display, the windows MenuBarAgent keeps and
//   the children they draw, as holzBar reads them; then, for each item of another app, whether a
//   drawn child overlaps its frame ("drawn") or none does ("not drawn").
//
// Options:
//   --redact   hide the names and paths in part A and replace the owners of non-Apple items in
//              part B with app1, app2, ...
//   --help
import AppKit
import ApplicationServices

// MARK: - Options and shared state

nonisolated(unsafe) var redact = false
nonisolated(unsafe) var aliases = [String: String]()

let agentBundleID = "com.apple.MenuBarAgent"
/// The limit for reading one application's extras bar in part A.
let partATimeout: Float = 0.25

func parseOptions() {
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--redact":
            redact = true
        case "--help", "-h":
            print("usage: swift not-shown-probe.swift [--redact]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
}

func out(_ line: String) {
    print(line)
}

// MARK: - Formatting

func shownOwner(_ bundleID: String) -> String {
    guard redact, !bundleID.hasPrefix("com.apple.") else {
        return bundleID
    }
    if let alias = aliases[bundleID] {
        return alias
    }
    let alias = "app\(aliases.count + 1)"
    aliases[bundleID] = alias
    return alias
}

func shownText(_ text: String?) -> String {
    guard let text else {
        return "-"
    }
    return redact ? "<redacted>" : "\"" + text + "\""
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

func extrasBar(of application: AXUIElement) -> AXUIElement? {
    guard let bar = attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
        return nil
    }
    // swiftlint:disable:next force_cast
    return (bar as! AXUIElement)
}

func displayID(at point: CGPoint) -> CGDirectDisplayID? {
    var display = CGDirectDisplayID(0)
    var matches: UInt32 = 0
    CGGetDisplaysWithPoint(point, 1, &display, &matches)
    return matches > 0 ? display : nil
}

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

// MARK: - Part A: owners without a bundle identifier

func partA() {
    out("")
    out("--- PART A: running applications without a bundle identifier ---")
    var asked = 0
    var owners = 0
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == nil {
        asked += 1
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, partATimeout)
        var barValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXExtrasMenuBarAttribute as CFString, &barValue)
        var count = 0
        if result == .success, let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            count = children(of: barValue as! AXUIElement).count
        }
        let name = shownText(app.localizedName)
        let path = shownText(app.executableURL?.path)
        if count > 0 {
            owners += 1
            out("  pid=\(app.processIdentifier) name=\(name) path=\(path) OWNS MENU BAR ITEMS: \(count)")
        } else {
            out("  pid=\(app.processIdentifier) name=\(name) path=\(path) extras bar children=0 (read result \(result.rawValue))")
        }
    }
    out("part A: \(asked) applications without a bundle identifier, \(owners) own menu bar items")
}

// MARK: - Part B: published but not drawn

struct Drawn {
    let display: CGDirectDisplayID
    let frame: CGRect
}

/// The children MenuBarAgent draws, per window, as holzBar reads them (a window child's own
/// first child when it has one).
func agentDrawn() -> [Drawn] {
    guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == agentBundleID }) else {
        out("MenuBarAgent is not running")
        return []
    }
    let application = AXUIElementCreateApplication(agent.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 1.0)
    var drawn = [Drawn]()
    let windows = (attribute(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    out("MenuBarAgent windows: \(windows.count)")
    for (number, window) in windows.enumerated() {
        let kids = children(of: window)
        out("  window #\(number) frame=\(shown(frame(of: window))) children=\(kids.count)")
        for child in kids {
            let hosted = children(of: child).first ?? child
            guard let rect = frame(of: hosted), let display = displayID(at: CGPoint(x: rect.midX, y: rect.midY)) else {
                continue
            }
            drawn.append(Drawn(display: display, frame: rect))
        }
    }
    return drawn
}

func partB() {
    out("")
    out("--- PART B: items published through Accessibility, drawn or not ---")
    let drawn = agentDrawn()
    for display in Set(drawn.map(\.display)).sorted() {
        let frames = drawn.filter { $0.display == display }.map(\.frame).sorted { $0.minX < $1.minX }
        out("display \(display): \(frames.count) drawn children")
        for rect in frames {
            out("  drawn \(shown(rect))")
        }
    }
    var published = 0
    var notDrawn = 0
    for app in NSWorkspace.shared.runningApplications {
        guard let bundleID = app.bundleIdentifier, bundleID != agentBundleID else {
            continue
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.4)
        guard let bar = extrasBar(of: application) else {
            continue
        }
        for (index, child) in children(of: bar).enumerated() {
            guard let rect = frame(of: child), rect.width > 4 else {
                continue
            }
            published += 1
            let display = displayID(at: CGPoint(x: rect.midX, y: rect.midY))
            let isDrawn = drawn.contains { $0.display == display && $0.frame.intersects(rect) }
            if !isDrawn {
                notDrawn += 1
            }
            out(String(format: "  %@ #%d frame=%@ d=%@: %@", shownOwner(bundleID), index, shown(rect), display.map { "\($0)" } ?? "-", isDrawn ? "drawn" : "not drawn"))
        }
    }
    out("part B: \(published) items of other apps published with a frame, \(notDrawn) not drawn")
}

// MARK: - Main

parseOptions()
setvbuf(stdout, nil, _IOLBF, 0)

guard AXIsProcessTrusted() else {
    out("This terminal has no Accessibility permission, so nothing can be read.")
    out("Open System Settings > Privacy & Security > Accessibility, switch on the terminal app you ran this in,")
    out("quit and reopen the terminal, and run the probe again.")
    exit(2)
}
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

let version = ProcessInfo.processInfo.operatingSystemVersion
out("=== holzBar not-shown-probe v1 ===")
out("redact=\(redact) at=\(ISO8601DateFormatter().string(from: Date()))")
out("macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) build=\(sysctlString("kern.osversion")) model=\(sysctlString("hw.model"))")
partA()
partB()
out("=== end of report ===")
