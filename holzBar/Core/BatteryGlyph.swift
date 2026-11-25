//
//  BatteryGlyph.swift
//  holzBar
//

import Foundation

/// Which battery symbol shows a charge, for the battery tile and the Large Percent widget alike,
/// so the two always agree (D-16).
nonisolated enum BatteryGlyph {
    /// The charges the symbols stand for.
    private static let steps = [0, 25, 50, 75, 100]

    /// The symbol shown while the battery charges.
    private static let chargingName = "battery.100percent.bolt"

    /// The battery symbol nearest to the charge: 0, 25, 50, 75 or 100 percent, with a bolt while
    /// it charges. A missing reading counts as empty.
    static func symbolName(percent: Int?, isCharging: Bool) -> String {
        if isCharging {
            return chargingName
        }
        let level = min(max(percent ?? 0, 0), 100)
        let nearest = steps.min { abs($0 - level) < abs($1 - level) } ?? 0
        return "battery.\(nearest)percent"
    }

    /// The symbol that shows the battery's state next to the percentage, if the state has one:
    /// a bolt while it charges, a plug on the adapter when it is full or holds its level, and
    /// nothing on battery power.
    static func stateSymbolName(for state: BatteryState?) -> String? {
        switch state {
        case .charging: "bolt.fill"
        case .charged, .onAdapter: "powerplug.fill"
        case .onBattery, nil: nil
        }
    }

    /// Every glyph ``symbolName(percent:isCharging:)`` can give: a widget measures its slot from
    /// the widest of them, so the item never changes width.
    static let symbolNames: [String] = steps.map { "battery.\($0)percent" } + [chargingName]
}
