//
//  BatteryLevel.swift
//  holzBar
//

import Foundation

/// Reads the numbers IOKit reports for a battery.
nonisolated enum BatteryLevel {
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
        let (scaled, overflow) = current.multipliedReportingOverflow(by: 100)
        if overflow {
            // An absurd capacity: saturate instead of trapping.
            return current > 0 ? Int.max / maximum : Int.min / maximum
        }
        return scaled / maximum
    }
}
