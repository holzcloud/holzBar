//
//  RehideClickTarget.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// Which window a click outside the menu bar hit, for smart rehide.
///
/// It used to be the topmost window with a title, but macOS withholds other apps' window
/// titles without Screen Recording, which smart rehide does not need, so smart rehide never
/// fired with only Accessibility. Layer, owner and bounds come without Screen Recording.
nonisolated enum RehideClickTarget {
    /// A window on screen, with what macOS tells without Screen Recording.
    struct Window: Equatable, Sendable {
        /// The window's layer number.
        var layer: Int
        /// The identifier of the process that owns the window.
        var ownerPID: pid_t
        /// The window's bounds, in screen coordinates.
        var bounds: CGRect
    }

    /// The index of the window that was clicked: the topmost window under the point below
    /// the cursor's level that is an app window (layer 0) or a window of the Dock, at any
    /// level (the wallpaper, the Dock itself).
    ///
    /// Floating panels and desktop-level windows of other apps, such as the Finder's desktop
    /// or Notification Center's widgets, are passed over.
    ///
    /// - Parameters:
    ///   - windows: The windows on screen, frontmost first.
    ///   - point: The click, in screen coordinates.
    ///   - cursorLayer: The cursor's window level; it and the levels above it are skipped.
    ///   - dockPID: The identifier of the Dock's process, if it runs.
    static func clickedWindowIndex(
        in windows: [Window],
        at point: CGPoint,
        cursorLayer: Int,
        dockPID: pid_t?
    ) -> Int? {
        windows.firstIndex { window in
            window.layer < cursorLayer &&
            window.bounds.contains(point) &&
            (window.layer == 0 || window.ownerPID == dockPID)
        }
    }
}
