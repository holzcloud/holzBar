//
//  ItemClicker27.swift
//  holzBar
//

import AppKit
@preconcurrency import ApplicationServices
import OSLog

/// Opens a hidden item's menu from the holzBar Shelf on macOS 27.
///
/// holzBar can no longer move an item into view. Its application is allowed for a moment, and
/// once the change that shows it has landed, the drawn item is clicked where it appears, the
/// way holzBar clicks items on earlier macOS, with the pointer put back afterwards. Until then
/// the item's frame is where it was last drawn, and another item or the clock may stand there.
/// An item whose show does not land within 3 s, or that is not drawn, such as one folded
/// behind the overflow button, is pressed through Accessibility. Menus open on the display
/// with the active menu bar, so if that is not the holzBar Shelf's display, holzBar first clicks the
/// empty spot of that display's menu bar where the holzBar Shelf was opened (measured on
/// macOS 27.0: that click makes the menu bar active). The click comes before the
/// application is shown, while the spot is still empty.
@available(macOS 27.0, *)
@MainActor
enum ItemClicker27 {
    private static let logger = Logger(category: "ItemClicker27")

    static func click(item: MenuBarItem, mouseButton: CGMouseButton, shelfDisplayID: CGDirectDisplayID?, appState: AppState) async {
        guard let bundleID = item.sourceApplication?.bundleIdentifier else {
            logger.error("No application for \(item.logString, privacy: .private(mask: .hash))")
            return
        }

        if
            ItemClick27.needsMenuBarActivation(activeDisplayID: Bridging.getActiveMenuBarDisplayID(), shelfDisplayID: shelfDisplayID),
            let shelfDisplayID,
            let point = appState.hidEventManager.lastEmptyMenuBarPoint(for: shelfDisplayID)
        {
            postMenuBarActivationClick(at: point)
            try? await Task.sleep(for: .milliseconds(300))
        }

        let concealer = appState.concealer27
        let shown = await concealer.showTemporarily(bundleID: bundleID)
        if shown {
            // A shown item is drawn 0.4–0.6 s after the change that allows it lands (measured).
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            logger.notice("\(item.logString, privacy: .private(mask: .hash)) was not shown in time, pressing it through Accessibility")
        }

        let ownerPID = item.ownerPID
        let baseline = Set(windowOwners().map { $0.number })
        var drawn: MenuBarItem?
        if shown {
            drawn = await MenuBarItemProvider27.items().first { $0.windowID == item.windowID && $0.isOnScreen }
        }
        if let drawn {
            postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
        } else if let element = MenuBarItemProvider27.element(forWindowID: item.windowID) {
            let action = mouseButton == .right ? kAXShowMenuAction : kAXPressAction
            let result = await perform(action, on: element)
            if result != .success {
                logger.notice("\(action, privacy: .public) on \(item.logString, privacy: .private(mask: .hash)) returned \(result.rawValue, privacy: .public)")
            }
        } else {
            logger.error("\(item.logString, privacy: .private(mask: .hash)) is neither drawn nor reachable through Accessibility")
            concealer.endTemporaryShow(bundleID: bundleID)
            return
        }

        // A click returns at once, and a press blocks only while a menu is open. Keep the
        // application shown until the menu or panel that opened is gone.
        try? await Task.sleep(for: .milliseconds(400))
        var waited = 0
        while waited < 240, ItemClick27.interfaceIsOpen(windowOwners: windowOwners(), ownerPID: ownerPID, baseline: baseline) {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        // "Hide opened items again after" counts from here, when the menu has closed
        // (THAW-13). One bounded wait; opening the item again meanwhile shows it once more,
        // and it stays until that show ends too.
        let delay = min(max(appState.settings.advanced.tempShowInterval, 0), 30)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        concealer.endTemporaryShow(bundleID: bundleID)
    }

    private static func perform(_ action: String, on element: AXUIElement) async -> AXError {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: AXUIElementPerformAction(element, action as CFString))
            }
        }
    }

    /// The menus on screen, with their owners: only menus keep an item shown
    /// (`InterfaceWindowRule`), never another window of its app (Thaw #1158).
    private static func windowOwners() -> [(number: Int, ownerPID: Int32)] {
        WindowInfo.createWindows(option: .onScreen)
            .filter { InterfaceWindowRule.menuLayers.contains($0.layer) }
            .map { window in
                (number: Int(window.windowID), ownerPID: window.ownerPID)
            }
    }

    private static func postMenuBarActivationClick(at point: CGPoint) {
        postClick(at: point, mouseButton: .left)
    }

    /// Posts a click marked so that holzBar's own mouse handlers ignore it, then puts the pointer back.
    private static func postClick(at point: CGPoint, mouseButton: CGMouseButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        let types: [CGEventType] = mouseButton == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: mouseButton) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: HIDEventManager.menuBarActivationMarker)
            event.post(tap: .cghidEventTap)
        }
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
    }
}
