//
//  WindowListBackend.swift
//  holzBar
//

import Cocoa

/// The menu bar backend of macOS 14 and 15.
///
/// Every menu bar item is a WindowServer window owned by the process that created it,
/// so the window list says which items there are and where. Items are moved and
/// clicked by posting events to them (``MenuBarItemEventPoster``).
@MainActor
final class WindowListBackend: MenuBarBackend {
    /// Posts the events that move and click items.
    let eventPoster = MenuBarItemEventPoster()

    var canMoveItems: Bool { true }

    var iconWindowShowsMenuBar: Bool { true }

    var itemChangeNotifications: [(NotificationCenter, Notification.Name)] { [] }

    var refreshesAfterApplicationActivation: Bool { false }

    var lastMoveOperationTimestamp: ContinuousClock.Instant? {
        eventPoster.lastMoveOperationTimestamp
    }

    func performSetup() async { }

    func items(on display: CGDirectDisplayID?, option: MenuBarItem.ListOption) async -> [MenuBarItem] {
        MenuBarItem.getMenuBarItemWindows(on: display, option: option).map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
    }

    func itemListSignature() async -> [CGWindowID] {
        Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
    }

    func cacheFromLayout(
        items: [MenuBarItem],
        displayID: CGDirectDisplayID?,
        appState: AppState
    ) -> MenuBarItemManager.ItemCache? {
        nil
    }

    func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination, appState: AppState) async throws {
        try await eventPoster.move(item: item, to: destination, appState: appState)
    }

    func click(item: MenuBarItem, with mouseButton: CGMouseButton, appState: AppState) async throws {
        try await eventPoster.click(item: item, with: mouseButton, appState: appState)
    }

    func isInsideItem(point: CGPoint, appState: AppState) -> Bool {
        let windowIDs = Bridging.getMenuBarWindowList(option: [.onScreen, .activeSpace, .itemsOnly])
        return windowIDs.contains { windowID in
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                return false
            }
            return bounds.contains(point)
        }
    }

    func isInsideItemsArea(point: CGPoint, screen: NSScreen, appState: AppState) -> Bool {
        // Between item windows the bar is empty.
        false
    }

    /// The split shape measures the item windows themselves.
    func itemsAreaLeftEdge(on screen: NSScreen, appState: AppState) -> CGFloat? {
        nil
    }

    func makeSystemItemClickBridge(appState: AppState) -> (any SystemItemClickBridge)? {
        nil
    }
}
