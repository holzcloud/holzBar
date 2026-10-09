//
//  ServiceBackend26.swift
//  holzBar
//

import Cocoa

/// The menu bar backend of macOS 26.
///
/// The items are still windows, but Control Center owns every one of them. The
/// process that created an item is looked up in holzBar through Accessibility, on
/// the cache's own queue (``SourcePIDCache``). Everything else works as on macOS 14
/// and 15, so the window-list backend does it.
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

    /// Starts the source-PID cache.
    func performSetup() async {
        await SourcePIDCache.shared.start()
    }

    /// The item windows, each with the source process that Accessibility names for it.
    ///
    /// holzBar's own control items are recognised by their frames instead
    /// (``OwnStatusItemWindows``), all of them before the one lookup for the other
    /// windows suspends, so holzBar's frames cannot change while the windows are
    /// matched. Control Center may lag behind them, updating its windows only a moment
    /// after an item changes its length or moves to another display, so a list read in
    /// between may not match until the next read.
    func items(on display: CGDirectDisplayID?, option: MenuBarItem.ListOption) async -> [MenuBarItem] {
        let windows = MenuBarItem.getMenuBarItemWindows(on: display, option: option)
        let controlItems = OwnStatusItemWindows.controlItems(forWindowBounds: windows.map(\.bounds))
        let lookups = zip(windows, controlItems).compactMap { window, controlItem in
            controlItem == nil ? window : nil
        }
        let sourcePIDs = lookups.isEmpty ? [:] : await SourcePIDCache.shared.pids(for: lookups)
        return zip(windows, controlItems).map { window, controlItem in
            if let controlItem {
                return MenuBarItem(uncheckedItemWindow: window, controlItem: controlItem)
            }
            return MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePIDs[window.windowID])
        }
    }

    func itemListSignature() async -> [CGWindowID] {
        await windowList.itemListSignature()
    }

    /// Whether the source-PID cache would look up one of the windows again
    /// (``SourcePIDCache/hasPendingLookups(in:)``).
    func hasPendingItemLookups(in signature: [CGWindowID]) async -> Bool {
        await SourcePIDCache.shared.hasPendingLookups(in: signature)
    }

    func itemListRefreshSkipped() {
        windowList.itemListRefreshSkipped()
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

    func itemsAreaLeftEdge(on screen: NSScreen, appState: AppState) -> CGFloat? {
        windowList.itemsAreaLeftEdge(on: screen, appState: appState)
    }

    func makeSystemItemClickBridge(appState: AppState) -> (any SystemItemClickBridge)? {
        windowList.makeSystemItemClickBridge(appState: appState)
    }
}
