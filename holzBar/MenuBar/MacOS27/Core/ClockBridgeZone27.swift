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
    ///   - ownItemFrames: The frames of holzBar's own control items. A click on one of them is
    ///     holzBar's own and is never bridged, whatever frame MenuBarAgent reports there.
    ///   - isConcealing: Whether items are concealed.
    ///   - menuBarRect: The rectangle of the clicked display's menu bar, or `nil` while the
    ///     bar is not on screen.
    static func shouldBridge(
        click: CGPoint,
        systemItemFrames: [CGRect],
        ownItemFrames: [CGRect] = [],
        isConcealing: Bool,
        menuBarRect: CGRect?
    ) -> Bool {
        guard isConcealing, let menuBarRect, menuBarRect.contains(click) else {
            return false
        }
        // A frame wider than half the bar is a host window spanning the bar, or a collapsed
        // control item's huge length, not an item; an empty one is a parked item.
        func isPlausible(_ frame: CGRect) -> Bool {
            !frame.isNull && frame.width > 0 && frame.height > 0 && frame.width <= menuBarRect.width / 2
        }
        if ownItemFrames.contains(where: { isPlausible($0) && $0.insetBy(dx: -1, dy: 0).contains(click) }) {
            return false
        }
        return systemItemFrames.contains { isPlausible($0) && $0.insetBy(dx: -1, dy: 0).contains(click) }
    }

    /// A window frame of AppKit (origin at the bottom left of the primary display) in
    /// the coordinates of event locations and Accessibility frames (origin at its top left).
    ///
    /// holzBar's control items report `window.frame`, which AppKit gives from the bottom
    /// left; compared with a click's location as it was, an item in the menu bar lay at the
    /// bottom of the screen and never contained the click.
    ///
    /// - Parameters:
    ///   - frame: The frame in AppKit coordinates.
    ///   - primaryHeight: The height of the primary display, whose top left is the origin.
    static func quartzFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        guard !frame.isNull, !frame.isInfinite, frame.origin.x.isFinite, frame.origin.y.isFinite else {
            return .null
        }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
