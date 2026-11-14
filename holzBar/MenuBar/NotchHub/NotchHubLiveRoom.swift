//
//  NotchHubLiveRoom.swift
//  holzBar
//

import Cocoa

/// Reads how much of the menu bar beside the notch is free, for the live state (concept section
/// 10b, "Live state: free span only"): the widened notch never covers a menu bar item.
///
/// Nothing here asks another application or the window server anew on a timer. It reads what
/// holzBar already follows: the application menu's frame (``ApplicationMenuFrames``, read off the
/// main thread when the frontmost application changes) and where the run of status items starts
/// (the backend's own read on macOS 27, the item windows on the earlier backends, which
/// ``MenuBarOverlayPanel``'s split shape reads the same way). Both are `@Observable` values or
/// follow the item cache, so a caller that reads this inside an observation loop is told when
/// either changes. The arithmetic is ``NotchHubGeometry/liveRoom(display:leftContentEnd:rightContentStart:)``.
@MainActor
enum NotchHubLiveRoom {
    /// The free room on each side of the notch on a screen.
    ///
    /// - Left: where the application menu ends. An application menu that is not known (no
    ///   Accessibility read yet, or one so long that it reaches the notch, which
    ///   ``ApplicationMenuFrames`` reports as none) counts as covering the side.
    /// - Right: where the run of status items starts. On macOS 27 the backend's read can be
    ///   missing (no items read yet); then the side counts as covering until the first read,
    ///   so the widened notch never covers an item it cannot see.
    static func room(on screen: NSScreen, display: NotchHubGeometry.Display, appState: AppState) -> NotchHubGeometry.LiveRoom {
        let displayBounds = CGDisplayBounds(screen.displayID)
        let leftContentEnd: Double = if let menu = appState.applicationMenuFrames.frame(for: screen) {
            Double(menu.maxX - displayBounds.minX)
        } else {
            .nan
        }
        return NotchHubGeometry.liveRoom(
            display: display,
            leftContentEnd: leftContentEnd,
            rightContentStart: itemsStart(on: screen, displayBounds: displayBounds, appState: appState)
        )
    }

    /// Where the run of status items starts on the screen, in x from the display's left edge, or
    /// `nil` when nothing is there (the side is free), not a number when nothing is known yet
    /// (the side counts as covered).
    private static func itemsStart(on screen: NSScreen, displayBounds: CGRect, appState: AppState) -> Double? {
        let itemManager = appState.itemManager
        // Reading the cache makes a caller's observation follow the item list on every backend.
        _ = itemManager.itemCache
        if let edge = itemManager.backend.itemsAreaLeftEdge(on: screen, appState: appState) {
            return Double(edge - displayBounds.minX)
        }
        guard MenuBarBackendKind.current != .accessibility27 else {
            // macOS 27 without a read: no position is known yet, so the side counts as covered
            // (not a number) until the first read of the items area arrives; that read posts
            // `menuBarItemsAreaDidChange27`, which lays the live shape out again.
            return .nan
        }
        // Before macOS 27 the item windows are the truth. A window that is not wholly on this
        // display is not an item of its bar (a collapsed divider reaches far to the left).
        let starts = MenuBarItem.getMenuBarItemWindows(on: screen.displayID, option: .onScreen)
            .map(\.bounds)
            .filter { displayBounds.contains($0) }
            .map(\.minX)
        return starts.min().map { Double($0 - displayBounds.minX) }
    }
}
