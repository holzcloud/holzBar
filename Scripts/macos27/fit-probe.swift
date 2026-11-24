// What fits beside the notch? Reads the menu bar items every app publishes, the notch and the
// system overflow control, then applies a simple "room" rule to them. Read-only: public
// Accessibility attribute reads with a short messaging timeout and AppKit/CoreGraphics geometry
// only. It sets no attribute, performs no action, posts no event, starts no process and opens no
// connection.
//
// Run it on a notched MacBook on macOS 27, once before and once after moving one app to Hidden in
// holzBar, and compare the two files:
//
//   swift Scripts/macos27/fit-probe.swift --label before-move 2>&1 | tee ~/Desktop/fit-before.txt
//   swift Scripts/macos27/fit-probe.swift --label after-move  2>&1 | tee ~/Desktop/fit-after.txt
//
// The terminal needs Accessibility (System Settings > Privacy & Security > Accessibility).
//
// What a run prints:
//   1. The macOS build.
//   2. Per screen: the display identifier, its frame, whether it has a notch, the widths of the
//      areas left and right of the notch and the notch span (as holzBar computes it), and which
//      display has the active menu bar.
//   3. The system overflow control's frame, or "none".
//   4. Every menu bar item of every running application: owner, frame, width and pitch (the width
//      minus the 2 points neighbouring items overlap by).
//   5. Per display: the assumed room (right area width minus 130 for the system items minus 17
//      for the overflow control), the sum of the pitches of the items drawn right of the notch and
//      how many of them fit by that rule, counting from the system items outwards.
//   6. A last summary line, "fit-probe <label>: control <present|absent>, <n> items right of the
//      notch, <m> fit by the rule".
//
// Options:
//   --label <text>   names the run in the output (free text, default "unlabelled")
//   --redact         replace the owners of non-Apple items with app1, app2, ...
//   --help
import AppKit
import ApplicationServices

// MARK: - Options and shared state

struct Options {
    var label = "unlabelled"
    var redact = false
}

nonisolated(unsafe) var options = Options()
nonisolated(unsafe) var aliases = [String: String]()

let agentBundleID = "com.apple.MenuBarAgent"
/// How far left of the clock the other system items reach (width of the system items).
let systemItemsSpan: CGFloat = 130
/// The width kept for the overflow control.
let controlWidth: CGFloat = 17
/// Neighbouring items overlap by this many points.
let itemOverlap: CGFloat = 2
/// Items closer to the notch than this still count as beside it, not under it.
let notchTolerance: CGFloat = 6

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
            print("usage: swift fit-probe.swift [--label before-move|after-move] [--redact]")
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

// MARK: - Formatting

func isApple(_ bundleID: String) -> Bool {
    bundleID.hasPrefix("com.apple.")
}

/// The owner as it is printed: the real bundle identifier, or `app<n>` for a non-Apple app with
/// --redact (numbered in the order first seen, consistent within one run only).
func shownOwner(_ bundleID: String) -> String {
    guard options.redact, !isApple(bundleID) else {
        return bundleID
    }
    if let alias = aliases[bundleID] {
        return alias
    }
    let alias = "app\(aliases.count + 1)"
    aliases[bundleID] = alias
    return alias
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

func extrasBar(of application: AXUIElement) -> AXUIElement? {
    guard let bar = attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
        return nil
    }
    // swiftlint:disable:next force_cast
    return (bar as! AXUIElement)
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
    let bounds: CGRect
    let hasNotch: Bool
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?
    let notch: ClosedRange<CGFloat>?
}

/// The horizontal span the notch covers, from the widths of the areas beside it (the same
/// arithmetic holzBar uses), or nil without a notch.
func notchSpan(bounds: CGRect, leftWidth: CGFloat?, rightWidth: CGFloat?) -> ClosedRange<CGFloat>? {
    guard let leftWidth, let rightWidth else {
        return nil
    }
    let minX = bounds.minX + leftWidth
    let maxX = bounds.maxX - rightWidth
    return minX < maxX ? minX...maxX : nil
}

func displays() -> [DisplayInfo] {
    NSScreen.screens.map { screen in
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let bounds = CGDisplayBounds(number)
        let left = screen.auxiliaryTopLeftArea?.width
        let right = screen.auxiliaryTopRightArea?.width
        return DisplayInfo(
            id: number,
            name: screen.localizedName,
            bounds: bounds,
            hasNotch: screen.safeAreaInsets.top > 0,
            leftWidth: left,
            rightWidth: right,
            notch: notchSpan(bounds: bounds, leftWidth: left, rightWidth: right)
        )
    }
}

func displayID(at point: CGPoint) -> CGDirectDisplayID? {
    var display = CGDirectDisplayID(0)
    var matches: UInt32 = 0
    CGGetDisplaysWithPoint(point, 1, &display, &matches)
    return matches > 0 ? display : nil
}

func activeDisplayID() -> CGDirectDisplayID? {
    NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}

func printHeader(_ screens: [DisplayInfo]) {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let formatter = ISO8601DateFormatter()
    out("=== holzBar fit-probe v1 ===")
    out("label=\(options.label) redact=\(options.redact) at=\(formatter.string(from: Date()))")
    out("macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) build=\(sysctlString("kern.osversion")) model=\(sysctlString("hw.model"))")
    if version.majorVersion < 27 {
        out("WARNING: this Mac runs macOS \(version.majorVersion), the probe is meant for macOS 27")
    }
    let active = activeDisplayID()
    for screen in screens {
        let notch = screen.notch.map { String(format: "span x=%.1f...%.1f (width %.1f)", $0.lowerBound, $0.upperBound, $0.upperBound - $0.lowerBound) } ?? "no span"
        let left = screen.leftWidth.map { String(format: "%.1f", $0) } ?? "-"
        let right = screen.rightWidth.map { String(format: "%.1f", $0) } ?? "-"
        out("display id=\(screen.id) \"\(screen.name)\" bounds=\(shown(screen.bounds)) notch=\(screen.hasNotch) leftArea=\(left) rightArea=\(right) \(notch)"
            + (screen.id == active ? " ACTIVE-MENU-BAR" : ""))
    }
    if active == nil {
        out("active menu bar display: unknown")
    }
}

// MARK: - Items

struct Item {
    let owner: String
    let index: Int
    let frame: CGRect
    var pitch: CGFloat { frame.width - itemOverlap }
}

/// The overflow control's frame: the AXButton child of MenuBarAgent's extras bar.
func controlFrame() -> CGRect? {
    guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == agentBundleID }) else {
        return nil
    }
    let application = AXUIElementCreateApplication(agent.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 1.0)
    guard let bar = extrasBar(of: application) else {
        return nil
    }
    for child in children(of: bar) where string(child, kAXRoleAttribute) == kAXButtonRole {
        return frame(of: child)
    }
    return nil
}

/// Every extras-bar item of every running application. MenuBarAgent's items are the hosting
/// groups' inner elements; its AXButton child is the control and is left out.
func scanItems() -> [Item] {
    var items = [Item]()
    for app in NSWorkspace.shared.runningApplications {
        guard let bundleID = app.bundleIdentifier else {
            continue
        }
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
            guard let rect = frame(of: element) else {
                continue
            }
            items.append(Item(owner: bundleID, index: index, frame: rect))
        }
    }
    return items
}

// MARK: - Report

struct Totals {
    var rightOfNotch = 0
    var fit = 0
}

func printItems(_ items: [Item], screens: [DisplayInfo]) {
    let sorted = items.sorted { $0.frame.minX < $1.frame.minX }
    out("ITEMS: \(items.count) extras-bar items with a frame, sorted by x (pitch = width - \(Int(itemOverlap)))")
    for item in sorted {
        let display = displayID(at: CGPoint(x: item.frame.midX, y: item.frame.midY))
        out(String(format: "  x=%8.1f y=%5.1f w=%6.1f pitch=%6.1f d=%@ ", item.frame.minX, item.frame.minY, item.frame.width, item.pitch, display.map { "\($0)" } ?? "-")
            + "\(shownOwner(item.owner)) #\(item.index)" + (item.owner == agentBundleID ? " (system)" : ""))
    }
}

/// The room rule per display. Only items of other apps are summed: the 130 points kept for the
/// system items already stand for MenuBarAgent's own.
func printRule(_ items: [Item], screens: [DisplayInfo]) -> Totals {
    var totals = Totals()
    for screen in screens {
        guard let notch = screen.notch, let right = screen.rightWidth else {
            out("RULE display \(screen.id): no notch, the rule does not apply")
            continue
        }
        let room = right - systemItemsSpan - controlWidth
        // Items drawn right of the notch, nearest the system items first.
        let beside = items.filter { item in
            guard item.owner != agentBundleID, item.frame.width > 4 else {
                return false
            }
            guard displayID(at: CGPoint(x: item.frame.midX, y: item.frame.midY)) == screen.id else {
                return false
            }
            return item.frame.minX + notchTolerance >= notch.upperBound
        }.sorted { $0.frame.minX > $1.frame.minX }
        let sum = beside.reduce(CGFloat(0)) { $0 + $1.pitch }
        var used: CGFloat = 0
        var fit = 0
        for item in beside {
            guard used + item.pitch <= room else {
                break
            }
            used += item.pitch
            fit += 1
        }
        totals.rightOfNotch += beside.count
        totals.fit += fit
        out(String(format: "RULE display %d: rightArea=%.1f assumedRoom=%.1f (rightArea - %.0f - %.0f) itemsRightOfNotch=%d pitchSum=%.1f fitByRule=%d", screen.id, right, room, systemItemsSpan, controlWidth, beside.count, sum, fit))
    }
    return totals
}

// MARK: - Main

options = parseOptions()
setvbuf(stdout, nil, _IOLBF, 0)

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
let control = controlFrame()
out("CONTROL (overflow) frame=\(shown(control))")
let items = scanItems()
printItems(items, screens: screens)
let totals = printRule(items, screens: screens)
out("fit-probe \(options.label): control \(control == nil ? "absent" : "present"), \(totals.rightOfNotch) items right of the notch, \(totals.fit) fit by the rule")
out("=== end of report ===")
