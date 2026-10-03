//
//  RevealTrigger.swift
//  holzBar
//

import Foundation

/// Decides when a reveal rule fires: once when its condition starts, not again while it
/// lasts.
nonisolated struct RevealTrigger {
    /// A Boolean value that indicates whether the condition held at the last update.
    private(set) var isActive = false

    /// Records the current state of the condition.
    ///
    /// - Parameter condition: Whether the condition holds now.
    /// - Returns: `true` only when the condition has just started.
    mutating func update(_ condition: Bool) -> Bool {
        defer {
            isActive = condition
        }
        return condition && !isActive
    }

    /// The battery level as a whole percentage, rounded down.
    ///
    /// - Parameters:
    ///   - current: The battery's current capacity.
    ///   - maximum: The battery's maximum capacity.
    /// - Returns: The level, or `nil` when the battery reports no maximum.
    static func percent(current: Int, maximum: Int) -> Int? {
        guard maximum > 0 else {
            return nil
        }
        return current * 100 / maximum
    }
}
