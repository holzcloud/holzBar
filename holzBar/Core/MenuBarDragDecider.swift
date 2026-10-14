//
//  MenuBarDragDecider.swift
//  holzBar
//

import Foundation

// On macOS the geometry members of CGRect and CGPoint live in CoreGraphics, which the app's
// member import visibility requires; on Linux Foundation provides them.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The hold-and-decide state machine of Drag in the Menu Bar.
///
/// A press on an app's menu bar item is held back. What the pointer does next decides what the
/// press was: a sideways move inside the bar makes it a ⌘ Command-drag, a move down out of the bar
/// a press that tracks the item's menu, and a release a plain click.
nonisolated struct MenuBarDragDecider: Equatable, Sendable {
    /// Where the gesture is.
    nonisolated enum State: Equatable, Sendable {
        /// No press is held and no drag is going on.
        case idle
        /// A press is held back since `time` (system uptime, in seconds).
        case holding(down: CGPoint, time: Double)
        /// The press became a ⌘ Command-drag.
        case dragging
        /// The press became a plain press that tracks a menu.
        case menuTracking
    }

    /// What the tap does with the event it just handed to the decider.
    nonisolated enum Action: Equatable, Sendable {
        /// Lets the event through unchanged.
        case pass

        /// Drops the event.
        case swallow

        /// Adds ⌘ Command and lets the event through.
        case rewriteWithCommand

        /// Drops the event and posts, marked, a ⌘ Command mouse-down at the held point and a
        /// ⌘ Command mouse-dragged at the event's point.
        case replayCommandDown(at: CGPoint)

        /// Drops the event and posts, marked, a plain mouse-down at the held point and a plain
        /// mouse-dragged at the event's point.
        case replayPlainDown(at: CGPoint)

        /// Drops the release and posts, marked, a plain mouse-down at `down` and a mouse-up at `up`.
        case replayClick(down: CGPoint, up: CGPoint)
    }

    /// How far, in points, the pointer must move sideways before a press is a drag.
    let threshold: CGFloat

    /// Where the gesture is.
    private(set) var state = State.idle

    init(threshold: CGFloat = 4) {
        self.threshold = threshold
    }

    /// The time of the press while it is held back.
    var heldSince: Double? {
        if case .holding(_, let time) = state {
            return time
        }
        return nil
    }

    /// Forgets any gesture, as when the tap is stopped in the middle of one.
    mutating func reset() {
        state = .idle
    }

    /// A press starts a new gesture; one on an item is held back.
    mutating func mouseDown(at point: CGPoint, time: Double, onItem: Bool) -> Action {
        guard onItem else {
            state = .idle
            return .pass
        }
        state = .holding(down: point, time: time)
        return .swallow
    }

    /// The pointer moved with the button down.
    mutating func mouseDragged(to point: CGPoint, time: Double, barMaxY: CGFloat) -> Action {
        switch state {
        case .holding(let down, _):
            if point.y > barMaxY {
                state = .menuTracking
                return .replayPlainDown(at: down)
            }
            if abs(point.x - down.x) >= threshold {
                state = .dragging
                return .replayCommandDown(at: down)
            }
            return .swallow
        case .dragging:
            return .rewriteWithCommand
        case .menuTracking, .idle:
            return .pass
        }
    }

    /// The button was released; the gesture is over.
    mutating func mouseUp(at point: CGPoint, time: Double) -> Action {
        let action: Action
        switch state {
        case .holding(let down, _):
            action = .replayClick(down: down, up: point)
        case .dragging:
            action = .rewriteWithCommand
        case .menuTracking, .idle:
            action = .pass
        }
        state = .idle
        return action
    }
}
