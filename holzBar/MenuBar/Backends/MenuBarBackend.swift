//
//  MenuBarBackend.swift
//  holzBar
//

import Cocoa

/// What differs between macOS generations in reading, hit testing, moving and
/// clicking menu bar items.
///
/// `MenuBarItemManager` and `HIDEventManager` ask the backend of the running macOS,
/// chosen once from ``MenuBarBackendKind`` (``MenuBarBackends/current``), instead of
/// branching on the macOS version themselves:
///
/// - ``WindowListBackend``: macOS 14 and 15, the window list and posted events.
/// - ``ServiceBackend26``: macOS 26, the window list with source processes from the
///   menu bar item service.
/// - ``AccessibilityBackend27``: macOS 27, Accessibility; items cannot be moved.
@MainActor
protocol MenuBarBackend: AnyObject {
    /// Whether menu bar items can be moved.
    var canMoveItems: Bool { get }

    /// Whether the holzBar icon's window tells whether the menu bar is on screen.
    var iconWindowShowsMenuBar: Bool { get }

    /// Notifications, besides launches, space and screen changes, after which the
    /// item list is read again.
    var itemChangeNotifications: [(NotificationCenter, Notification.Name)] { get }

    /// Whether the item list is read again soon after another application becomes active.
    var refreshesAfterApplicationActivation: Bool { get }

    /// When an item was last moved.
    var lastMoveOperationTimestamp: ContinuousClock.Instant? { get }

    /// Prepares the backend at launch.
    func performSetup() async

    /// Returns the menu bar items on the given display, ordered left to right.
    func items(on display: CGDirectDisplayID?, option: MenuBarItem.ListOption) async -> [MenuBarItem]

    /// A value that changes whenever the items on the active space change.
    func itemListSignature() async -> [CGWindowID]

    /// Called when a refresh found the item list unchanged and did not rebuild the cache,
    /// so work that rides on the refreshes can run anyway.
    func itemListRefreshSkipped()

    /// Builds the item cache from the saved layout, or returns `nil` where the order
    /// of the items on the bar decides their sections.
    func cacheFromLayout(
        items: [MenuBarItem],
        displayID: CGDirectDisplayID?,
        appState: AppState
    ) -> MenuBarItemManager.ItemCache?

    /// Moves an item to the given destination.
    func move(item: MenuBarItem, to destination: MenuBarItemManager.MoveDestination, appState: AppState) async throws

    /// Clicks an item with the given mouse button.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton, appState: AppState) async throws

    /// Whether the given point, in CoreGraphics coordinates, is on a menu bar item.
    func isInsideItem(point: CGPoint, appState: AppState) -> Bool

    /// Whether the given point, in CoreGraphics coordinates, is in the part of the bar
    /// that holds items, including the gaps between them.
    func isInsideItemsArea(point: CGPoint, screen: NSScreen, appState: AppState) -> Bool

    /// Creates the tap that lets clicks reach the system items while items are
    /// concealed, where the backend needs one.
    func makeSystemItemClickBridge(appState: AppState) -> (any SystemItemClickBridge)?
}

/// A tap that `HIDEventManager` starts and stops with its other monitors.
@MainActor
protocol SystemItemClickBridge: AnyObject {
    /// Starts the tap.
    func start()

    /// Stops the tap.
    func stop()
}

/// The backend of the running macOS.
@MainActor
enum MenuBarBackends {
    /// The backend for the running macOS, chosen once from ``MenuBarBackendKind/current``.
    static let current: any MenuBarBackend = {
        switch MenuBarBackendKind.current {
        case .windowList:
            return WindowListBackend()
        case .service26:
            if #available(macOS 26.0, *) {
                return ServiceBackend26()
            }
            return WindowListBackend()
        case .accessibility27:
            if #available(macOS 27.0, *) {
                return AccessibilityBackend27()
            }
            return WindowListBackend()
        }
    }()
}
