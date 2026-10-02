//
//  HoverSchedule.swift
//  holzBar
//

import Foundation

/// Keeps at most one delayed hover action pending.
///
/// Show on hover runs its handler on every mouse move. Each move used to start a task that
/// slept for the hover delay, so moving the pointer started dozens of them. The schedule
/// lets only the first move that asks for an action start one; later moves that ask for the
/// same action start nothing, so the delay still counts from the first move. A move that
/// asks for another action replaces the pending one.
struct HoverSchedule<Action: Equatable> {
    /// The action waiting for its delay, if any.
    private(set) var pending: Action?

    /// Counts the actions started, so only the current one clears ``pending``.
    private var generation = 0

    /// Asks to perform `action` after the delay.
    ///
    /// - Parameter action: The action the pointer asks for.
    /// - Returns: The generation of the new action, which replaces any other pending one,
    ///   or `nil` when the same action is already pending and nothing needs to start.
    mutating func request(_ action: Action) -> Int? {
        if pending == action {
            return nil
        }
        pending = action
        generation += 1
        return generation
    }

    /// Marks the action of the given generation as done, so the next request starts again.
    ///
    /// An older generation, already replaced by another action, changes nothing.
    mutating func finish(_ generation: Int) {
        if generation == self.generation {
            pending = nil
        }
    }

    /// Forgets the pending action.
    mutating func cancel() {
        pending = nil
    }
}
