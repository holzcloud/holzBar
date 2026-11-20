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

    /// The last click from the Shelf in fixed words (how the item was reached, and whether it
    /// took the click), for Copy Diagnostics. Never a name. Empty before the first click.
    static var lastClick = ""

    /// Tells the user that a click on a Shelf tile did not reach its item: a system beep, and an
    /// announcement for VoiceOver. The Shelf has closed by then, so nothing else stays to show it.
    private static func reportFailure(_ words: String) {
        lastClick = words
        NSSound.beep()
        AccessibilityNotification.Announcement(String(localized: "The item did not open.")).post()
    }

    static func click(item: MenuBarItem, mouseButton: CGMouseButton, shelfDisplayID: CGDirectDisplayID?, appState: AppState) async {
        guard let bundleID = item.sourceApplication?.bundleIdentifier else {
            logger.error("No application for \(item.logString, privacy: .private(mask: .hash))")
            reportFailure("failed, no application")
            return
        }

        await activateMenuBarIfNeeded(shelfDisplayID: shelfDisplayID, appState: appState)

        let concealer = appState.concealer27
        // MenuBarAgent cannot name this application's item, so allowing the application would
        // not bring it back: every concealment is released instead (``UnnameableApps27``).
        if concealer.isConcealing, concealer.isUnnameable(item.sourceApplication) {
            await clickUnnameable(item: item, mouseButton: mouseButton, appState: appState)
            return
        }
        let shown = await concealer.showTemporarily(bundleID: bundleID)
        if shown {
            // A shown item is drawn 0.4–0.6 s after the change that allows it lands (measured).
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            logger.notice("\(item.logString, privacy: .private(mask: .hash)) was not shown in time, pressing it through Accessibility")
        }

        let ownerPID = item.ownerPID
        // Every window at a menu's level that is on screen before the click, of any height, is
        // no menu the click opened.
        let baseline = Set(menuLevelWindows().map(\.windowID).map(Int.init))
        var drawn: MenuBarItem?
        if shown {
            drawn = await MenuBarItemProvider27.items().first { $0.windowID == item.windowID && $0.isOnScreen }
        }
        if let drawn {
            postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
            lastClick = "shown, clicked"
        } else if let element = MenuBarItemProvider27.element(forWindowID: item.windowID) {
            let action = mouseButton == .right ? kAXShowMenuAction : kAXPressAction
            let result = await perform(action, on: element)
            if result == .success {
                lastClick = shown ? "not drawn, pressed" : "not shown in time, pressed"
            } else {
                logger.notice("\(action, privacy: .public) on \(item.logString, privacy: .private(mask: .hash)) returned \(result.rawValue, privacy: .public)")
                reportFailure("press refused, code \(result.rawValue)")
            }
        } else {
            logger.error("\(item.logString, privacy: .private(mask: .hash)) is neither drawn nor reachable through Accessibility")
            reportFailure(shown ? "failed, not drawn and not reachable" : "failed, not shown and not reachable")
            concealer.endTemporaryShow(bundleID: bundleID)
            return
        }

        // A click returns at once, and a press blocks only while a menu is open. Keep the
        // application shown until the menu or panel that opened is gone.
        await waitForMenuToClose(ownerPID: ownerPID, baseline: baseline)
        // "Hide opened items again after" counts from here, when the menu has closed
        // (THAW-13). One bounded wait; opening the item again meanwhile shows it once more,
        // and it stays until that show ends too.
        let delay = min(max(appState.settings.advanced.tempShowInterval, 0), 30)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        concealer.endTemporaryShow(bundleID: bundleID)
    }

    /// Opens the menu of an item MenuBarAgent cannot name, which stays hidden while holzBar
    /// conceals anything: every concealment is released, the item is clicked where it is drawn,
    /// and concealment returns as soon as the menu has closed.
    ///
    /// The hold ends when the menu is gone, with no extra delay, so that every hidden item is
    /// drawn for as short a time as possible. An item not drawn within 3 s of the release is
    /// reported as failed, and it is never clicked twice: a second click would close its menu
    /// or toggle its action.
    private static func clickUnnameable(item: MenuBarItem, mouseButton: CGMouseButton, appState: AppState) async {
        let concealer = appState.concealer27
        await ReleaseHold27.withHold(
            begin: { await concealer.holdReleased() },
            end: { concealer.endHoldReleased() },
            body: { landed in await clickReleased(item: item, mouseButton: mouseButton, landed: landed) }
        )
    }

    /// The work inside the hold of ``clickUnnameable(item:mouseButton:appState:)``: waits for the
    /// item to be drawn, clicks it once and waits for its menu to close.
    private static func clickReleased(item: MenuBarItem, mouseButton: CGMouseButton, landed: Bool) async {
        guard landed else {
            logger.notice("The release for \(item.logString, privacy: .private(mask: .hash)) did not land")
            reportFailure("release refused")
            return
        }
        // A released item is drawn 0.4–0.6 s after the change lands (measured).
        let landedAt = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(600))
        var drawn: MenuBarItem?
        while true {
            drawn = await MenuBarItemProvider27.items().first { $0.windowID == item.windowID && $0.isOnScreen }
            if drawn != nil || ContinuousClock.now - landedAt >= drawBudget {
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let drawn else {
            logger.notice("\(item.logString, privacy: .private(mask: .hash)) was not drawn after the release")
            reportFailure("released, not drawn")
            return
        }
        let ownerPID = item.ownerPID
        let baseline = Set(menuLevelWindows().map(\.windowID).map(Int.init))
        postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
        lastClick = "released, clicked"
        await waitForMenuToClose(ownerPID: ownerPID, baseline: baseline)
    }

    /// How long an item is waited for after the release that should draw it.
    private static let drawBudget = Duration.seconds(3)

    /// Waits until the menu or panel an item opened is gone, watched on the panel watch
    /// schedule (4 times a second for 10 s, then once a second, for up to 10 minutes).
    private static func waitForMenuToClose(ownerPID: Int32, baseline: Set<Int>) async {
        try? await Task.sleep(for: .milliseconds(400))
        let watchStart = ContinuousClock.now
        while
            ItemClick27.interfaceIsOpen(windowOwners: openMenus(ownerPID: ownerPID), ownerPID: ownerPID, baseline: baseline),
            let interval = ItemClick27.panelWatchInterval(elapsed: ContinuousClock.now - watchStart)
        {
            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }
        }
    }

    /// Makes the menu bar of the holzBar Shelf's display the active one, where it is not: a
    /// click on the empty spot where the Shelf was opened. Shared by every click that comes
    /// from the Shelf, which must run before the application is shown.
    static func activateMenuBarIfNeeded(shelfDisplayID: CGDirectDisplayID?, appState: AppState) async {
        guard
            ItemClick27.needsMenuBarActivation(activeDisplayID: Bridging.getActiveMenuBarDisplayID(), shelfDisplayID: shelfDisplayID),
            let shelfDisplayID,
            let point = appState.hidEventManager.lastEmptyMenuBarPoint(for: shelfDisplayID)
        else {
            return
        }
        postMenuBarActivationClick(at: point)
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func perform(_ action: String, on element: AXUIElement) async -> AXError {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: AXUIElementPerformAction(element, action as CFString))
            }
        }
    }

    /// The windows on screen at the levels of menus, of any height and owner.
    private static func menuLevelWindows() -> [WindowInfo] {
        WindowInfo.createWindows(option: .onScreen).filter { InterfaceWindowRule.menuLayers.contains($0.layer) }
    }

    /// The open menus of the given application on screen, with their owners: only menus keep an
    /// item shown, never another window of its app (Thaw #1158).
    ///
    /// The rule is the one the hides of the sections use (`InterfaceWindowRule.isOpenMenu`): a
    /// pop-up menu counts, a window at the status bar's level only when it is taller than the
    /// bar (a popover or a panel; every status item's own window sits at that level), and an
    /// application menu never. Otherwise the item's own window, drawn after the click, or a
    /// menu bar window of the activated application kept the item shown for the whole watch.
    private static func openMenus(ownerPID: Int32) -> [(number: Int, ownerPID: Int32)] {
        // The tallest menu bar of every display, the notch included.
        let barHeight = NSScreen.screens.reduce(NSStatusBar.system.thickness) { height, screen in
            max(height, screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        }
        return menuLevelWindows()
            .filter { window in
                InterfaceWindowRule.isOpenMenu(
                    layer: window.layer,
                    height: window.bounds.height,
                    ownerPID: window.ownerPID,
                    shownOwners: [ownerPID],
                    barHeight: barHeight
                )
            }
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
