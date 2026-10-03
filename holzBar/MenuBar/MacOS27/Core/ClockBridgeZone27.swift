//
//  ClockBridgeZone27.swift
//  holzBar
//

import CoreGraphics

/// Decides whether a click must be let through to a system item.
///
/// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on
/// the clock (measured on macOS 27.0), so such clicks lift the assertion first.
///
/// Only a click inside the menu bar's own rectangle, while the bar is on screen, is a
/// click on the bar: a click just below the clock over a maximised window, or near it in a
/// fullscreen app with the bar hidden, belongs to the app underneath (Thaw #1171, #1191).
nonisolated enum ClockBridgeZone27 {
    /// - Parameters:
    ///   - click: The click's location.
    ///   - systemItemFrames: The frames of the system items on the clicked display.
    ///   - isConcealing: Whether items are concealed.
    ///   - menuBarRect: The rectangle of the clicked display's menu bar, or `nil` while the
    ///     bar is not on screen.
    static func shouldBridge(click: CGPoint, systemItemFrames: [CGRect], isConcealing: Bool, menuBarRect: CGRect?) -> Bool {
        guard isConcealing, let menuBarRect, menuBarRect.contains(click) else {
            return false
        }
        return systemItemFrames.contains { $0.insetBy(dx: -1, dy: 0).contains(click) }
    }
}
