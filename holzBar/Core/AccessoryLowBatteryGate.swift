//
//  AccessoryLowBatteryGate.swift
//  holzBar
//

import Foundation

/// Decides when a low battery is announced: once per descent to or below the threshold.
///
/// An accessory that sits at or below the threshold alerts once and then stays quiet. It is
/// armed again when its level rises more than ``hysteresis`` points above the threshold, or
/// when it leaves the list (it was switched off or unpaired). Charging is not reported, so a
/// rising level is the only sign of it. The first reading counts: an accessory that is
/// already low when the runtime starts is announced once.
nonisolated struct AccessoryLowBatteryGate {
    /// How far above the threshold a level must rise before the next descent alerts again.
    static let hysteresis = 5

    /// The ids announced and not yet re-armed.
    private var announced = Set<String>()

    /// Feeds one reading.
    ///
    /// - Parameters:
    ///   - levels: The percentage of every accessory in the reading, by id.
    ///   - threshold: The level at or below which an accessory is low.
    /// - Returns: The ids that alert now, sorted.
    mutating func update(levels: [String: Int], threshold: Int) -> [String] {
        announced.formIntersection(levels.keys)
        var alerting = [String]()
        for (id, level) in levels {
            if announced.contains(id) {
                if level > threshold + Self.hysteresis {
                    announced.remove(id)
                }
            } else if level <= threshold {
                announced.insert(id)
                alerting.append(id)
            }
        }
        return alerting.sorted()
    }

    /// Forgets every id, so the next reading counts as a first one.
    mutating func reset() {
        announced.removeAll()
    }
}
