//
//  RevealAnimationSchedule.swift
//  holzBar
//

import Foundation

/// The pure steps of one movement of a section divider's length.
///
/// On macOS 14 to 26 a hidden section is a divider 10 000 points long that pushes the items
/// to its left off the screen. Showing the section used to assign the short length at once,
/// so every item appeared in the same frame. A schedule lists the lengths in between, so
/// the items slide in or out instead. It only says what the lengths are and when; applying
/// them (and cancelling them) is `RevealStepRunner`'s job, and whether to animate at all is
/// `RevealAnimationPolicy`'s.
nonisolated struct RevealAnimationSchedule: Equatable, Sendable {
    /// Which way the divider moves.
    nonisolated enum Direction: Sendable {
        /// The divider's length falls and the section's items come in.
        case reveal
        /// The divider's length rises and the section's items go out.
        case hide
    }

    /// One length to assign.
    nonisolated struct Step: Equatable, Sendable {
        /// Seconds after the start.
        let time: Double
        /// The length in points.
        let length: Double
    }

    /// How long a movement takes, in seconds. Nothing animates for longer than 0.4 s.
    static let duration = 0.18

    /// How many steps a second the schedule has.
    static let stepsPerSecond = 60.0

    /// The length of a hidden section's divider, which is `ControlItem`'s expanded length.
    static let expandedLength = 10_000.0

    /// The direction of the movement.
    let direction: Direction

    /// The lengths to assign, in order. Empty when the change is instant.
    let steps: [Step]

    /// A Boolean value that indicates whether there is nothing to animate.
    var isInstant: Bool {
        steps.isEmpty
    }

    /// Maps a fraction of the duration (clamped to 0 through 1) to a fraction of the
    /// distance: a reveal slows down as the items arrive, a hide speeds up as they leave.
    static func eased(_ fraction: Double, direction: Direction) -> Double {
        let time = min(max(fraction, 0), 1)
        switch direction {
        case .reveal:
            let remaining = 1 - time
            return 1 - remaining * remaining * remaining
        case .hide:
            return time * time * time
        }
    }

    /// Makes the schedule that moves a divider from `start` to `end`.
    ///
    /// The schedule is empty, so the change is instant, when the duration is not positive,
    /// when a length is not a finite number, when `start` and `end` are equal, or when the
    /// lengths do not move the way `direction` says (a reveal needs `end` below `start`, a
    /// hide needs it above). The last step is exactly `end`.
    static func make(
        direction: Direction,
        from start: Double,
        to end: Double,
        duration: Double = duration
    ) -> RevealAnimationSchedule {
        let movesTheRightWay = direction == .reveal ? end < start : end > start
        guard start.isFinite, end.isFinite, duration.isFinite, duration > 0, movesTheRightWay else {
            return RevealAnimationSchedule(direction: direction, steps: [])
        }
        let count = max(1, Int((duration * stepsPerSecond).rounded()))
        let steps = (1...count).map { index -> Step in
            let fraction = Double(index) / Double(count)
            let length = index == count
                ? end
                : start + (end - start) * eased(fraction, direction: direction)
            return Step(time: duration * fraction, length: length)
        }
        return RevealAnimationSchedule(direction: direction, steps: steps)
    }

    /// The length at which the nearest item of a section begins to enter the status area.
    ///
    /// A divider's right edge stays where it is whatever its length. The nearest item of the
    /// section stands to the left of the divider, so it is just at the right edge of the
    /// application menus when the divider is as long as the space between that edge and the
    /// divider's right edge. A shorter divider shows it. Stepping from any longer length
    /// would only move items nobody can see.
    ///
    /// This is a hypothesis about where the items begin to show, to be adjusted when it is
    /// seen on a Mac.
    ///
    /// - Returns: The length, at most ``expandedLength``, or `nil` when it is not above
    ///   `endLength` (nothing to travel) or an input is not a finite number.
    static func startLength(dividerMaxX: Double, applicationMenuMaxX: Double, endLength: Double) -> Double? {
        guard dividerMaxX.isFinite, applicationMenuMaxX.isFinite, endLength.isFinite, endLength >= 0 else {
            return nil
        }
        let length = min(dividerMaxX - applicationMenuMaxX, expandedLength)
        return length > endLength ? length : nil
    }
}
