// Finds out whether macOS 27 lets a menu bar item be moved with a ⌘ Command-drag,
// which holzIce would need to reorder items on the bar itself (holzIce feature 16).
//
// Run on macOS 27 with Accessibility granted to the terminal, and holzIce quit:
//   swiftc -O Scripts/macos27/reorder-probe.swift -o /tmp/reorder-probe && /tmp/reorder-probe
//
// It takes the two leftmost application items, ⌘-drags the first past the second,
// reads the order again and prints REORDER WORKS or REORDER BLOCKED. Drag it back by
// hand afterwards if it moved.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let v = value(element, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &position) }
    if let v = value(element, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
    return CGRect(origin: position, size: size)
}

struct Item {
    let bundleID: String
    let frame: CGRect
}

func items() -> [Item] {
    var result = [Item]()
    for app in NSWorkspace.shared.runningApplications {
        guard let bundleID = app.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else { continue }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard
            let bar = value(application, kAXExtrasMenuBarAttribute),
            let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
        else { continue }
        for child in children {
            let f = frame(child)
            if f.width > 0 { result.append(Item(bundleID: bundleID, frame: f)) }
        }
    }
    return result.sorted { $0.frame.minX < $1.frame.minX }
}

let source = CGEventSource(stateID: .hidSystemState)
func mouse(_ type: CGEventType, _ point: CGPoint, command: Bool) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    if command { event?.flags = .maskCommand }
    event?.post(tap: .cghidEventTap)
}

let before = items()
guard before.count >= 2 else {
    print("Need at least two application items in the menu bar, found \(before.count)")
    exit(1)
}
let (first, second) = (before[0], before[1])
print("Before: \(before.map(\.bundleID).joined(separator: " "))")
print("Dragging \(first.bundleID) past \(second.bundleID)")

let from = CGPoint(x: first.frame.midX, y: first.frame.midY)
let to = CGPoint(x: second.frame.maxX + 2, y: second.frame.midY)
mouse(.mouseMoved, from, command: true); usleep(200_000)
mouse(.leftMouseDown, from, command: true); usleep(300_000)
for step in 1...30 {
    let t = CGFloat(step) / 30
    mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y), command: true)
    usleep(20_000)
}
usleep(300_000)
mouse(.leftMouseUp, to, command: true)
usleep(1_500_000)

let after = items()
print("After:  \(after.map(\.bundleID).joined(separator: " "))")
let firstIndex = after.firstIndex { $0.bundleID == first.bundleID } ?? 0
let secondIndex = after.firstIndex { $0.bundleID == second.bundleID } ?? 0
print(firstIndex > secondIndex ? "REORDER WORKS" : "REORDER BLOCKED")
