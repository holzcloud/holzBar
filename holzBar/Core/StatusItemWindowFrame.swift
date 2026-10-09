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

    /// Returns how far apart, in points, the farthest edges of the window with the given
    /// bounds, from the window list, and of the window with the given frame in AppKit's
    /// screen coordinates are, or `nil` when the frame has no size or an edge is farther
    /// apart than ``tolerance``.
    static func edgeDistance(_ windowBounds: CGRect, appKitFrame: CGRect, primaryScreenHeight: CGFloat) -> CGFloat? {
        guard appKitFrame.width > 0, appKitFrame.height > 0 else {
            return nil
        }
        let expected = self.windowBounds(fromAppKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight)
        let distance = max(
            abs(expected.minX - windowBounds.minX),
            abs(expected.maxX - windowBounds.maxX),
            abs(expected.minY - windowBounds.minY),
            abs(expected.maxY - windowBounds.maxY)
        )
        return distance <= tolerance ? distance : nil
    }

    /// Returns a Boolean value that indicates whether the window with the given bounds, from
    /// the window list, is the window with the given frame in AppKit's screen coordinates.
    static func matches(_ windowBounds: CGRect, appKitFrame: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        edgeDistance(windowBounds, appKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight) != nil
    }

    /// Returns, for each of the given window bounds from the window list, the index of the
    /// AppKit frame whose window it is, or `nil` for a window that matches none of them.
    ///
    /// Each frame goes to one window at most, and each window gets one frame at most. Two
    /// dividers of length 0 next to each other are 1 point wide and 1 point apart (measured
    /// on macOS 26.7.1), so each of their windows lies within the tolerance of both frames.
    /// The closest pairs are assigned first; a tie goes to the earlier frame, then to the
    /// earlier window, so the result does not depend on chance.
    static func assign(windowBounds: [CGRect], toAppKitFrames frames: [CGRect], primaryScreenHeight: CGFloat) -> [Int?] {
        var pairs = [(distance: CGFloat, frame: Int, window: Int)]()
        for (window, bounds) in windowBounds.enumerated() {
            for (frame, appKitFrame) in frames.enumerated() {
                if let distance = edgeDistance(bounds, appKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight) {
                    pairs.append((distance, frame, window))
                }
            }
        }
        pairs.sort { $0 < $1 }

        var assignment = [Int?](repeating: nil, count: windowBounds.count)
        var assignedFrames = Set<Int>()
        for pair in pairs where assignment[pair.window] == nil && !assignedFrames.contains(pair.frame) {
            assignment[pair.window] = pair.frame
            assignedFrames.insert(pair.frame)
        }
        return assignment
    }
}
