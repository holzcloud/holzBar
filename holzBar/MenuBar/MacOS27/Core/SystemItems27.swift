//
//  SystemItems27.swift
//  holzBar
//

import Foundation

/// MenuBarAgent's numbered system items on macOS 27.
///
/// Measured with `Scripts/macos27/system-item-probe.swift` on macOS 27.0 (2026-09-29).
nonisolated enum SystemItems27 {
    /// The numbers that draw an item on macOS 27.0: 0 is the battery, 2 the clock,
    /// 6 Wi-Fi and 8 Control Centre.
    static let drawn: Set<Int> = [0, 2, 6, 8]

    /// The highest number measured: MenuBarAgent accepted every number from 0 to this one,
    /// offered one at a time and all together in one live assertion.
    static let highestMeasured = 127

    /// The numbers holzBar keeps on the bar: all measured ones, so a system item that a later
    /// build numbers above 8 stays visible. holzBar hides applications' items, not the system's.
    static let allowed: ClosedRange<Int> = 0...highestMeasured
}
