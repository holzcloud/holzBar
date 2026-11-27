// Measures what happens to a click on a system item (Wi-Fi by default) while holzBar conceals
// items, when a concealed item sits to the right of it (issue #151).
//
// holzBar holds such a click back, lifts concealment and replays it. The lift brings every
// concealed item back, so an item with a concealed one to its right moves left under the
// replayed click. This probe clicks the item with a real click and reports, per round:
//
// - how the item's Accessibility frame moves after the click (when it starts, how far, when
//   it is back), which says whether the frame can be trusted as the place to click;
// - which process opened a window (the item's own panel, or a neighbour's menu);
// - whether the panel went away by itself before the probe closed it.
//
// usage: system-item-shift-probe [click|press] [identifier suffix] [rounds]
//        click (default): a real click.   press: an Accessibility press, no click.
//        identifier suffix: wifi (default), battery, clock, ...
//
// Build: swiftc -O Scripts/macos27/system-item-shift-probe.swift -o /tmp/holzbar-shift-probe
// Requirements: holzBar running with at least one hidden item (best: one to the right of the
// probed item), Accessibility for the terminal that runs it. Takes the pointer.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard
        let positionValue = value(element, kAXPositionAttribute),
        let sizeValue = value(element, kAXSizeAttribute),
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

func milliseconds(since start: TimeInterval) -> Int {
    Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
}

/// The windows on screen at or above the menu bar's level: number, owner and size.
func highWindows() -> [Int: (owner: String, pid: pid_t, size: CGSize)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
    var result = [Int: (owner: String, pid: pid_t, size: CGSize)]()
    for window in list {
        guard
            let number = window[kCGWindowNumber] as? Int,
            let layer = window[kCGWindowLayer] as? Int, layer >= 20,
            let pid = window[kCGWindowOwnerPID] as? pid_t,
            let boundsValue = window[kCGWindowBounds] as? [String: CGFloat]
        else {
            continue
        }
        let size = CGSize(width: boundsValue["Width"] ?? 0, height: boundsValue["Height"] ?? 0)
        let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            ?? (window[kCGWindowOwnerName] as? String) ?? "pid \(pid)"
        result[number] = (owner, pid, size)
    }
    return result
}

func post(_ type: CGEventType, at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func postEscape() {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let mode = arguments.first { ["click", "press"].contains($0) } ?? "click"
let rounds = arguments.compactMap { Int($0) }.first ?? 10
let suffix = arguments.first { !["click", "press"].contains($0) && Int($0) == nil } ?? "wifi"

guard AXIsProcessTrusted() else {
    print("This terminal has no Accessibility permission (System Settings > Privacy & Security > Accessibility).")
    exit(2)
}
guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
    print("MenuBarAgent is not running")
    exit(2)
}
let application = AXUIElementCreateApplication(agent.processIdentifier)
AXUIElementSetMessagingTimeout(application, 0.5)

/// The system item whose identifier ends with the suffix. Each system item is a hosting group;
/// its identifier and frame belong to the item inside it.
func findItem() -> AXUIElement? {
    guard
        let bar = value(application, kAXExtrasMenuBarAttribute),
        let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
    else {
        return nil
    }
    return children
        .compactMap { (value($0, kAXChildrenAttribute) as? [AXUIElement])?.first }
        .first { ((value($0, kAXIdentifierAttribute) as? String) ?? "").hasSuffix(suffix) }
}

guard let item = findItem(), let restFrame = frame(item) else {
    print("no system item ending in \"\(suffix)\"")
    exit(2)
}
print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), mode \(mode), item \(suffix) at x \(Int(restFrame.minX))...\(Int(restFrame.maxX)), \(rounds) rounds")

var ownPanel = 0
var otherWindow = 0
var nothing = 0
var closedBySelf = 0
var largestShift: CGFloat = 0
let pointer = CGEvent(source: nil)?.location

for round in 1...rounds {
    guard let before = frame(item) else {
        print("round \(round): the item has no frame")
        continue
    }
    let point = CGPoint(x: before.midX, y: before.midY)
    let baseline = Set(highWindows().keys)
    post(.mouseMoved, at: point)
    usleep(80_000)
    let start = ProcessInfo.processInfo.systemUptime
    if mode == "press" {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
    } else {
        post(.leftMouseDown, at: point)
        usleep(20_000)
        post(.leftMouseUp, at: point)
    }

    // The item's frame, every 5 ms for a second: only the changes are kept.
    var timeline = [(ms: Int, x: Int)]()
    var lastX = Int(before.minX.rounded())
    var opened: (ms: Int, owner: String, number: Int)?
    var samples = 0
    while ProcessInfo.processInfo.systemUptime - start < 1.0 {
        if let now = frame(item) {
            let x = Int(now.minX.rounded())
            largestShift = max(largestShift, abs(now.minX - before.minX))
            if x != lastX {
                timeline.append((milliseconds(since: start), x))
                lastX = x
            }
        }
        samples += 1
        if opened == nil, samples.isMultiple(of: 4) {
            let windows = highWindows()
            if let new = windows.first(where: { !baseline.contains($0.key) && $0.value.size.height > 60 }) {
                opened = (milliseconds(since: start), new.value.owner, new.key)
            }
        }
        usleep(5_000)
    }
    let moves = timeline.isEmpty ? "frame did not move" : "frame x \(Int(before.minX.rounded())) " + timeline.map { "→\($0.x)@\($0.ms)ms" }.joined(separator: " ")

    guard let opened else {
        nothing += 1
        print("round \(round): NOTHING opened; \(moves)")
        usleep(1_200_000)
        continue
    }
    let isOwn = opened.owner == "com.apple.controlcenter" || opened.owner == "com.apple.notificationcenterui"
    if isOwn {
        ownPanel += 1
    } else {
        otherWindow += 1
    }
    // Left alone for 2.5 s: a panel that goes by itself was closed by something else.
    var wentAfter: Int?
    while ProcessInfo.processInfo.systemUptime - start < 3.5 {
        if highWindows()[opened.number] == nil {
            wentAfter = milliseconds(since: start)
            break
        }
        usleep(50_000)
    }
    if wentAfter != nil {
        closedBySelf += 1
    }
    print("round \(round): \(isOwn ? "own panel" : "OTHER WINDOW") of \(opened.owner) after \(opened.ms) ms\(wentAfter.map { ", CLOSED BY ITSELF after \($0) ms" } ?? ""); \(moves)")
    if wentAfter == nil {
        postEscape()
    }
    usleep(1_500_000)
}

if let pointer {
    post(.mouseMoved, at: pointer)
}
print("""
summary: \(rounds) rounds, own panel \(ownPanel), other window \(otherWindow), nothing \(nothing), \
closed by itself \(closedBySelf), largest frame shift \(Int(largestShift.rounded())) pt
""")
exit(otherWindow == 0 && nothing == 0 && closedBySelf == 0 ? 0 : 1)
