//
//  ItemOpener.swift
//  holzBar
//

import AppKit
@preconcurrency import ApplicationServices
import OSLog

/// The one way holzBar opens a menu bar item's menu for the user: the holzBar Shelf, the
/// search, groups, item hotkeys, the item hints and the Shortcuts action all call
/// ``MenuBarItemManager/openItem(_:mouseButton:shelfDisplayID:)``.
extension MenuBarItemManager {
    /// Opens the menu of the given item.
    ///
    /// With "Open hidden items in the menu bar" off, a hidden item is pressed through
    /// Accessibility without being shown; when the app does not take the press, it is
    /// shown as usual. Otherwise, on macOS 27 the item's application is shown for the click
    /// (`ItemClicker27`); before, an item on screen is clicked and a hidden one is shown for
    /// a moment and clicked.
    ///
    /// - Parameters:
    ///   - item: The item to open.
    ///   - mouseButton: `.left` for the item's menu, `.right` for its secondary menu.
    ///   - shelfDisplayID: The display of the holzBar Shelf the item was clicked in, if any.
    func openItem(_ item: MenuBarItem, mouseButton: CGMouseButton, shelfDisplayID: CGDirectDisplayID?) async {
        if
            let appState,
            !appState.settings.advanced.openHiddenItemsInMenuBar,
            isHidden(item, appState: appState)
        {
            if await pressWithoutShowing(item, mouseButton: mouseButton) {
                return
            }
            Logger.default.debug("A hidden item did not take the press, so it is shown")
        }
        if #available(macOS 27.0, *), let appState {
            await ItemClicker27.click(item: item, mouseButton: mouseButton, shelfDisplayID: shelfDisplayID, appState: appState)
            return
        }
        if Bridging.isWindowOnScreen(item.windowID) {
            do {
                try await click(item: item, with: mouseButton)
            } catch {
                Logger.default.error("Error opening menu bar item: \(error, privacy: .private)")
            }
        } else {
            await temporarilyShow(item: item, clickingWith: mouseButton)
        }
    }

    /// Whether the item is hidden now: its application concealed on macOS 27, off screen
    /// before.
    private func isHidden(_ item: MenuBarItem, appState: AppState) -> Bool {
        if #available(macOS 27.0, *) {
            guard let pid = item.sourcePID else {
                return false
            }
            return appState.concealer27.concealedPIDs.contains(pid)
        }
        return !Bridging.isWindowOnScreen(item.windowID)
    }

    /// Presses a hidden item through Accessibility without showing it.
    ///
    /// The press runs off the main thread and every call to the app waits 0.25 s at most,
    /// so an app that hangs cannot block holzBar.
    ///
    /// - Returns: Whether the app took the press.
    private func pressWithoutShowing(_ item: MenuBarItem, mouseButton: CGMouseButton) async -> Bool {
        let action = mouseButton == .right ? kAXShowMenuAction : kAXPressAction
        let knownElement: AXUIElement? = if #available(macOS 27.0, *) {
            MenuBarItemProvider27.element(forWindowID: item.windowID)
        } else {
            nil
        }
        let pid = item.sourcePID ?? item.ownerPID
        let bounds = item.bounds
        let result: AXError = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let element = knownElement ?? MenuBarItemManager.extrasMenuBarElement(pid: pid, matching: bounds) else {
                    continuation.resume(returning: .failure)
                    return
                }
                AXUIElementSetMessagingTimeout(element, 0.25)
                continuation.resume(returning: AXUIElementPerformAction(element, action as CFString))
            }
        }
        return result == .success
    }

    /// The child of the app's extras menu bar at the item's place (before macOS 27).
    private nonisolated static func extrasMenuBarElement(pid: pid_t, matching bounds: CGRect) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let extrasMenuBar = AXHelpers.extrasMenuBar(for: application) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(extrasMenuBar, 0.25)
        return AXHelpers.children(for: extrasMenuBar).first { child in
            AXUIElementSetMessagingTimeout(child, 0.25)
            guard let frame = AXHelpers.frame(for: child) else {
                return false
            }
            return abs(frame.minX - bounds.minX) < 2 && abs(frame.width - bounds.width) < 2
        }
    }

    /// The cached item stored under the given identity key, if it is in the menu bar now.
    func item(withIdentityKey stored: String) -> MenuBarItem? {
        let key = storedIdentityKey(stored)
        return itemCache.managedItems.first { item in
            identityKey(for: item) == key
        }
    }

    /// Opens the menu of the item stored under the given identity key (an item's hotkey).
    func openItem(withIdentityKey key: String) {
        guard let item = item(withIdentityKey: key) else {
            Logger.default.notice("The item of a hotkey is not in the menu bar")
            NSSound.beep()
            return
        }
        Task {
            await openItem(item, mouseButton: .left, shelfDisplayID: nil)
        }
    }
}
