//
//  ServiceBackend26.swift
//  holzBar
//

import Cocoa

/// The menu bar backend of macOS 26.
///
/// The items are still windows, but Control Center owns every one of them. The
/// process that created an item comes from the menu bar item service, which asks
/// Accessibility in the XPC service. Everything else works as on macOS 14 and 15,
/// so the window-list backend does it.
@available(macOS 26.0, *)
@MainActor
final class ServiceBackend26: MenuBarBackend {
    /// The backend that moves, clicks and hit tests the item windows.
    private let windowList = WindowListBackend()

    var canMoveItems: Bool { windowList.canMoveItems }

    var iconWindowShowsMenuBar: Bool { windowList.iconWindowShowsMenuBar }

    var itemChangeNotifications: [(NotificationCenter, Notification.Name)] { windowList.itemChangeNotifications }

    var refreshesAfterApplicationActivation: Bool { windowList.refreshesAfterApplicationActivation }

    var lastMoveOperationTimestamp: ContinuousClock.Instant? { windowList.lastMoveOperationTimestamp }

    /// Starts the menu bar item service.
    func performSetup() async {
        await MenuBarItemService.Connection.shared.start()
    }

    /// The item windows, each with the process the item service names as its source.
    func items(on display: CGDirectDisplayID?, option: MenuBarItem.ListOption) async -> [MenuBarItem] {
        var items = [MenuBarItem]()
        for window in MenuBarItem.getMenuBarItemWindows(on: display, option: option) {
            let sourcePID = await MenuBarItemService.Connection.shared.sourcePID(for: window)
            items.append(MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePID))
        }
        return items
    }

    func itemListSignature() async -> [CGWindowID] {
        await windowList.itemListSignature()
    }

    func cacheFromLayout(
        items: [MenuBarItem],
        displayID: CGDirectDisplayID?,
        appState: AppState
    ) -> MenuBarItemManager.ItemCache? {
        windowList.cacheFromLayout(items: items, displayID: displayID, appState: appState)
    }

    func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination, appState: AppState) async throws {
        try await windowList.move(item: item, to: destination, appState: appState)
    }

    func click(item: MenuBarItem, with mouseButton: CGMouseButton, appState: AppState) async throws {
        try await windowList.click(item: item, with: mouseButton, appState: appState)
    }

    func isInsideItem(point: CGPoint, appState: AppState) -> Bool {
        windowList.isInsideItem(point: point, appState: appState)
    }

    func isInsideItemsArea(point: CGPoint, screen: NSScreen, appState: AppState) -> Bool {
        windowList.isInsideItemsArea(point: point, screen: screen, appState: appState)
    }

    func makeSystemItemClickBridge(appState: AppState) -> (any SystemItemClickBridge)? {
        windowList.makeSystemItemClickBridge(appState: appState)
    }
}
