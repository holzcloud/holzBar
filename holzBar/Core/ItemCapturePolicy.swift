//
//  ItemCapturePolicy.swift
//  holzBar
//

import CoreGraphics

/// Bounds the blocking window captures of item images before macOS 27 (F-13).
///
/// A window capture is a synchronous call that, on macOS 26, can block its thread forever.
/// Every call is given up after ``timeout``; the ``Watchdog`` decides what follows, and
/// ``isOnScreen(_:displays:)`` keeps the single captures away from the windows that are
/// known to block.
nonisolated enum ItemCapturePolicy {
    /// How long a capture call may take before it is given up.
    ///
    /// About a hundred times a normal call, so only a call that is stuck ends here.
    static let timeout = Duration.seconds(2)

    /// How many queues stuck in a capture call stop item image capture for the session.
    ///
    /// Each one keeps a thread blocked until holzBar quits.
    static let maxAbandonedQueues = 3

    /// How far, in points, an item may reach past the edge of a display and still count
    /// as on it.
    ///
    /// Window bounds carry fractions of a point on scaled displays. Hidden items sit
    /// thousands of points off screen, so the tolerance never lets one in.
    static let displayTolerance: CGFloat = 1

    /// Returns whether the given window bounds lie entirely on one of the given displays.
    ///
    /// Both are in the window list's global coordinate space, with its origin at the top
    /// left of the primary display, as `CGDisplayBounds` and `Bridging.getWindowBounds`
    /// report them. Bounds without a width are never on screen.
    static func isOnScreen(_ bounds: CGRect, displays: [CGRect]) -> Bool {
        guard !bounds.isEmpty, bounds.width > 0 else {
            return false
        }
        return displays.contains { display in
            display.insetBy(dx: -displayTolerance, dy: -displayTolerance).contains(bounds)
        }
    }

    /// Tracks the capture calls that did not return in time.
    struct Watchdog: Sendable {
        /// What the image cache does after a capture call timed out.
        enum Action: Equatable, Sendable {
            /// Send later captures to a fresh queue.
            case replaceQueue
            /// Stop item image capture until holzBar is relaunched.
            case stop
        }

        /// The number of queues abandoned with a call that did not return.
        private(set) var abandonedQueues = 0

        /// The windows whose single capture did not return.
        private(set) var hungWindowIDs = Set<CGWindowID>()

        /// Whether item image capture has stopped for the session.
        var isStopped: Bool {
            abandonedQueues >= ItemCapturePolicy.maxAbandonedQueues
        }

        /// Returns whether the given window is skipped, because its capture did not return.
        func skips(_ windowID: CGWindowID) -> Bool {
            hungWindowIDs.contains(windowID)
        }

        /// Records a capture call that did not return in time and returns what follows.
        ///
        /// - Parameter windowID: The window of a single capture, or `nil` for a composite
        ///   capture, which covers many windows and so names no hung one.
        mutating func recordTimeout(windowID: CGWindowID?) -> Action {
            abandonedQueues += 1
            if let windowID {
                hungWindowIDs.insert(windowID)
            }
            return isStopped ? .stop : .replaceQueue
        }

        /// Forgets the hung windows that no longer exist.
        mutating func forgetWindows(notIn existing: Set<CGWindowID>) {
            hungWindowIDs.formIntersection(existing)
        }
    }
}
