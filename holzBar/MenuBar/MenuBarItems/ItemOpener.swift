//
//  ItemOpener.swift
//  holzBar
//

import AppKit
import OSLog

/// The one way holzBar opens a menu bar item's menu for the user.
extension MenuBarItemManager {
    /// Opens the menu of the given item.
    ///
    /// On macOS 27 the item's application is shown for the click (`ItemClicker27`); before,
    /// an item on screen is clicked and a hidden one is shown for a moment and clicked.
    ///
    /// - Parameters:
    ///   - item: The item to open.
    ///   - mouseButton: `.left` for the item's menu, `.right` for its secondary menu.
    ///   - shelfDisplayID: The display of the holzBar Shelf the item was clicked in, if any.
    func openItem(_ item: MenuBarItem, mouseButton: CGMouseButton, shelfDisplayID: CGDirectDisplayID?) async {
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
