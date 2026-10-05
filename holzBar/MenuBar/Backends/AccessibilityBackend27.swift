//
//  AccessibilityBackend27.swift
//  holzBar
//

import Cocoa

/// The menu bar backend of macOS 27.
///
/// MenuBarAgent draws the items without WindowServer windows, so they are read,
/// hit tested and clicked through Accessibility (``MenuBarItemProvider27``,
/// ``ItemHitTest27``, ``ItemClicker27``). They cannot be moved: the saved layout
/// decides their sections, and concealment hides them.
@available(macOS 27.0, *)
@MainActor
final class AccessibilityBackend27: MenuBarBackend {
    /// Notices item changes of the processes that own items.
    private let itemChangeObserver = ItemChangeObserver27()

    var canMoveItems: Bool { false }

    /// On macOS 27 the icon's window is only a placeholder, and its frame says nothing
    /// about the menu bar (measured past a display's left edge, below its bottom, and
    /// with no height).
    var iconWindowShowsMenuBar: Bool { false }

    var itemChangeNotifications: [(NotificationCenter, Notification.Name)] {
        [(NotificationCenter.default, .menuBarItemsMayHaveChanged27)]
    }

    /// Accessibility reports frames only for the active menu bar, so the items are read
    /// again soon after it moves to another display.
    var refreshesAfterApplicationActivation: Bool { true }

    var lastMoveOperationTimestamp: ContinuousClock.Instant? { nil }

    /// There are no item windows: bounds come from Accessibility, and the owning
    /// process is known directly, without the item service.
    func performSetup() async {
        Bridging.setSyntheticWindowBoundsProvider { MenuBarItemProvider27.currentBounds(for: $0) }
    }

    func items(on display: CGDirectDisplayID?, option: MenuBarItem.ListOption) async -> [MenuBarItem] {
        // Accessibility only describes the display with the active menu bar.
        if let display, display != Bridging.getActiveMenuBarDisplayID() {
            return []
        }
        let items = await MenuBarItemProvider27.items()
        return option.contains(.onScreen) ? items.filter(\.isOnScreen) : items
    }

    /// There is no item window list. A reorder keeps the synthetic identifiers, so the
    /// signature also carries each item's position.
    func itemListSignature() async -> [CGWindowID] {
        let items = await MenuBarItemProvider27.items()
        return items.map { item in
            // A conversion that cannot trap, whatever position the item's process reports,
            // and that truncates like the `Int(_:)` before it, so signatures stay as they were.
            let minX = Int32(exactly: item.bounds.minX.rounded(.towardZero)) ?? 0
            return item.windowID &+ UInt32(bitPattern: minX)
        }
    }

    /// Owners whose observer registration failed are tried again once their pause is over,
    /// also while the item list stays the same.
    func itemListRefreshSkipped() {
        itemChangeObserver.retryDueRegistrations()
    }

    /// The saved layout, not the order on the bar, places items in sections, so holzBar's
    /// dividers are not needed. Accessibility reports them only on the display holzBar
    /// launched on, and requiring them emptied the cache on the other display. An upgrade
    /// from an earlier macOS arrives with its sections in the bar's order and nowhere else,
    /// so the first readable bar is where they come from.
    func cacheFromLayout(
        items: [MenuBarItem],
        displayID: CGDirectDisplayID?,
        appState: AppState
    ) -> MenuBarItemManager.ItemCache? {
        // Observe the processes that own items now; observers of quit ones go.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        itemChangeObserver.observe(owners: Set(items.map(\.ownerPID).filter { $0 != ownPID }))
        // An application that launched while concealed is concealed once its item exists.
        appState.concealer27.itemsAppeared(bundleIDs: Set(items.map { $0.tag.namespace.description }))
        appState.concealer27.seedLayoutIfNeeded(items: items)
        appState.concealer27.placeNewApplications(items: items)
        return appState.concealer27.cacheFromSavedLayout(items: items, displayID: displayID)
    }

    func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination, appState: AppState) async throws {
        throw MenuBarItemManager.EventError.itemNotMovable(item)
    }

    func click(item: MenuBarItem, with mouseButton: CGMouseButton, appState: AppState) async throws {
        await ItemClicker27.click(item: item, mouseButton: mouseButton, shelfDisplayID: nil, appState: appState)
    }

    func isInsideItem(point: CGPoint, appState: AppState) -> Bool {
        ItemHitTest27.isInsideItem(
            point: point,
            items: hitTestItems(appState: appState),
            concealedPIDs: appState.concealer27.concealedPIDs,
            systemFrames: systemFrames(),
            drawnFramesOnDisplay: drawnFrames(at: point)
        )
    }

    func isInsideItemsArea(point: CGPoint, screen: NSScreen, appState: AppState) -> Bool {
        ItemHitTest27.isInsideItemsArea(
            point: point,
            displayBounds: CGDisplayBounds(screen.displayID),
            items: hitTestItems(appState: appState),
            concealedPIDs: appState.concealer27.concealedPIDs,
            systemFrames: systemFrames(),
            rememberedLeftEdge: MenuBarItemProvider27.leftEdge(for: screen.displayID),
            drawnFramesOnDisplay: MenuBarItemProvider27.drawnFrames(for: screen.displayID)
        )
    }

    /// The edge of the items area as the split shape draws it (`SplitShape27`), from the
    /// cache and the last read: no Accessibility call, so the overlay can ask while it draws.
    func itemsAreaLeftEdge(on screen: NSScreen, appState: AppState) -> CGFloat? {
        SplitShape27.leftEdge(
            displayBounds: CGDisplayBounds(screen.displayID),
            items: hitTestItems(appState: appState),
            concealedPIDs: appState.concealer27.concealedPIDs,
            systemFrames: systemFrames(),
            rememberedLeftEdge: MenuBarItemProvider27.leftEdge(for: screen.displayID),
            drawnFramesOnDisplay: MenuBarItemProvider27.drawnFrames(for: screen.displayID)
        )
    }

    func makeSystemItemClickBridge(appState: AppState) -> (any SystemItemClickBridge)? {
        SystemItemClickBridge27(appState: appState)
    }

    /// The cached items, as `ItemHitTest27` takes them.
    private func hitTestItems(appState: AppState) -> [ItemHitTest27.Item] {
        appState.itemManager.itemCache.managedItems.map { item in
            ItemHitTest27.Item(frame: item.bounds, ownerPID: item.ownerPID, isOnScreen: item.isOnScreen)
        }
    }

    /// The frames MenuBarAgent draws on the display under the point, when that display's bar
    /// is not active (`ItemHitTest27`).
    private func drawnFrames(at point: CGPoint) -> [CGRect] {
        var displayID = CGDirectDisplayID(0)
        var matches: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &displayID, &matches)
        return matches > 0 ? MenuBarItemProvider27.drawnFrames(for: displayID) : []
    }

    /// The frames of the system items and the overflow button, from the last read.
    private func systemFrames() -> [CGRect] {
        MenuBarItemProvider27.systemItemFrames() + [MenuBarItemProvider27.overflowButtonFrame()].compactMap { $0 }
    }
}
