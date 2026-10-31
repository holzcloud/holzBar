//
//  AccessoryAlertOptions.swift
//  holzBar
//

import Foundation

/// The switches of the Accessory alerts module: which kinds of event raise an alert.
///
/// Connect alerts are on by default. Disconnect alerts are off, because AirPods in and out of
/// their case disconnect often. Low-battery alerts are on, at 20 percent.
nonisolated struct AccessoryAlertOptions: Equatable, Sendable {
    /// Whether a device that connects raises an alert.
    var connect: Bool
    /// Whether a device that disconnects raises an alert.
    var disconnect: Bool
    /// Whether an accessory whose battery is low raises an alert.
    var lowBattery: Bool = true
    /// The level, in percent, at or below which a battery is low.
    var lowBatteryLevel: Int = AccessoryAlertOptions.defaultLowBatteryLevel

    /// The options of a user who changed nothing.
    static let `default` = AccessoryAlertOptions(connect: true, disconnect: false)

    /// The levels the low-battery stepper offers.
    static let lowBatteryLevelRange = 10...30
    /// The low-battery level of a user who changed nothing.
    static let defaultLowBatteryLevel = 20

    /// A stored low-battery level kept in ``lowBatteryLevelRange`` and rounded to a whole
    /// percentage; the default when it is not a finite number.
    ///
    /// The defaults can hold anything, so the model clamps what it reads.
    static func clampedLevel(_ value: Double) -> Int {
        let rule = SettingsSchema.NumberRule.clamped(Double(lowBatteryLevelRange.lowerBound)...Double(lowBatteryLevelRange.upperBound))
        return Int(rule.clamp(value, fallback: Double(defaultLowBatteryLevel)).rounded())
    }

    /// Whether a low battery raises an alert at all.
    var allowsLowBattery: Bool {
        lowBattery
    }

    /// Whether an event raises an alert.
    func allows(_ event: AccessoryEvent) -> Bool {
        switch event {
        case .connected: connect
        case .disconnected: disconnect
        }
    }
}
