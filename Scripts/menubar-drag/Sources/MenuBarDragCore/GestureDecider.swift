//
//  GestureDecider.swift
//  holzBar
//

import CoreGraphics

/// The hold-and-decide state machine of mechanism a2.
///
/// A press on an app item is held back. What the pointer does next decides what the press was:
/// a sideways move inside the bar makes it a Command-drag, a move down out of the bar makes it a
/// press that tracks a menu, and a release makes it a plain click.
public struct GestureDecider: Sendable, Equatable {
    /// Where the gesture is.
    public enum State: Sendable, Equatable {
        case idle
        case holding(down: CGPoint, time: Double)
        case dragging
        case menuTracking
    }

    /// What the tap does with the event it just handed to the decider.
    public enum Action: Sendable, Equatable {
        /// Lets the event through unchanged.
        case pass

        /// Drops the event.
        case swallow

        /// Adds Command and lets the event through.
        case rewriteWithCommand

        /// Drops the event and posts, marked, a Command mouse-down at the held point and a Command
        /// mouse-dragged at the event's point.
        case replayCommandDown(at: CGPoint)

        /// Drops the event and posts, marked, a plain mouse-down at the held point and a plain
        /// mouse-dragged at the event's point.
        case replayPlainDown(at: CGPoint)

        /// Drops the release and posts, marked, a plain mouse-down at `down` and a mouse-up at `up`.
        case replayClick(down: CGPoint, up: CGPoint)
    }

    /// How far, in points, the pointer must move sideways before a press is a drag.
    public let threshold: CGFloat

    public private(set) var state = State.idle

    public init(threshold: CGFloat = 4) {
        self.threshold = threshold
    }

    /// The time of the press while it is held back.
    public var heldSince: Double? {
        if case .holding(_, let time) = state {
            return time
        }
        return nil
    }

    /// A press resets the decider; one on an item is held back.
    public mutating func mouseDown(at point: CGPoint, time: Double, onItem: Bool) -> Action {
        guard onItem else {
            state = .idle
            return .pass
        }
        state = .holding(down: point, time: time)
        return .swallow
    }

    public mutating func mouseDragged(to point: CGPoint, time: Double, barMaxY: CGFloat) -> Action {
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

    public mutating func mouseUp(at point: CGPoint, time: Double) -> Action {
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
