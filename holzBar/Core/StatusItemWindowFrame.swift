//
//  StatusItemWindowFrame.swift
//  holzBar
//

import CoreGraphics

/// Finds the window that draws one of holzBar's status items on macOS 26.
///
/// On macOS 26 Control Center draws every status item in a window of its own, and the
/// item's `NSWindow` in holzBar has a window number that is no window server identifier
/// (measured on macOS 26.7.1: 1 << 32, 2 << 32, …). Its frame, though, is the frame of
/// the item's Control Center window, also while a divider is expanded (both 5016 points
/// wide) or collapsed (measured with two displays: the copy on the second display has
/// other bounds and is not matched).
nonisolated enum StatusItemWindowFrame {
    /// How far apart, in points, the edges of the same window may be in the two descriptions.
    static let tolerance: CGFloat = 1

    /// Returns the bounds, as the window list describes them (origin at the top left of the
    /// primary display), of the window with the given frame in AppKit's screen coordinates
    /// (origin at the bottom left of the primary display).
    static func windowBounds(fromAppKitFrame frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Returns a Boolean value that indicates whether the window with the given bounds, from
    /// the window list, is the window with the given frame in AppKit's screen coordinates.
    static func matches(_ windowBounds: CGRect, appKitFrame: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        guard appKitFrame.width > 0, appKitFrame.height > 0 else {
            return false
        }
        let expected = self.windowBounds(fromAppKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight)
        return abs(expected.minX - windowBounds.minX) <= tolerance &&
            abs(expected.maxX - windowBounds.maxX) <= tolerance &&
            abs(expected.minY - windowBounds.minY) <= tolerance &&
            abs(expected.maxY - windowBounds.maxY) <= tolerance
    }
}
