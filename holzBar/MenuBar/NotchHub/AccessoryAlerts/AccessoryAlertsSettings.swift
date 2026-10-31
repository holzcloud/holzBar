//
//  AccessoryAlertsSettings.swift
//  holzBar
//

import Observation

/// Model for the Accessory alerts module's own settings: whether a connecting accessory, a
/// disconnecting one and a low battery each raise an alert, the level that counts as low, and
/// whether battery levels are read at all. Each saves itself in its `didSet`.
///
/// The runtime does not keep a copy: it reads ``options()`` at each decision, so a change takes
/// effect at once and nothing observes the defaults.
@MainActor
@Observable
final class AccessoryAlertsSettings {
    /// A Boolean value that indicates whether an accessory that connects raises an alert. On by
    /// default.
    var connect = AccessoryAlertOptions.default.connect {
        didSet {
            Defaults.set(connect, forKey: .accessoryAlertsOnConnect)
        }
    }

    /// A Boolean value that indicates whether an accessory that disconnects raises an alert. Off
    /// by default.
    var disconnect = AccessoryAlertOptions.default.disconnect {
        didSet {
            Defaults.set(disconnect, forKey: .accessoryAlertsOnDisconnect)
        }
    }

    /// A Boolean value that indicates whether an accessory whose battery is low raises an
    /// alert. On by default.
    var lowBattery = AccessoryAlertOptions.default.lowBattery {
        didSet {
            Defaults.set(lowBattery, forKey: .accessoryAlertsOnLowBattery)
        }
    }

    /// The level, in percent, at or below which a battery is low, from 10 to 30.
    var lowBatteryLevel = AccessoryAlertOptions.default.lowBatteryLevel {
        didSet {
            Defaults.set(lowBatteryLevel, forKey: .accessoryAlertsLowBatteryLevel)
        }
    }

    /// A Boolean value that indicates whether the module reads accessory battery levels. That
    /// is the one macOS call Apple does not document, so this is the switch that turns it off.
    /// On by default.
    var readsBattery = AccessoryAlertsSettings.readsBattery() {
        didSet {
            Defaults.set(readsBattery, forKey: .accessoryAlertsReadsBattery)
        }
    }

    /// Loads the stored values. An absent key, or a value of the wrong type, keeps the default;
    /// the level is kept within 10 to 30.
    init() {
        let stored = Self.options()
        connect = stored.connect
        disconnect = stored.disconnect
        lowBattery = stored.lowBattery
        lowBatteryLevel = stored.lowBatteryLevel
    }

    /// The switches as stored now, with the defaults for what is absent.
    static func options() -> AccessoryAlertOptions {
        var options = AccessoryAlertOptions.default
        Defaults.ifPresent(key: .accessoryAlertsOnConnect, assign: &options.connect)
        Defaults.ifPresent(key: .accessoryAlertsOnDisconnect, assign: &options.disconnect)
        Defaults.ifPresent(key: .accessoryAlertsOnLowBattery, assign: &options.lowBattery)
        // The defaults can hold anything, so the level is clamped, not trusted.
        var level = Double(options.lowBatteryLevel)
        Defaults.ifPresent(key: .accessoryAlertsLowBatteryLevel, assign: &level)
        options.lowBatteryLevel = AccessoryAlertOptions.clampedLevel(level)
        return options
    }

    /// Whether battery levels are read, as stored now. On when the key is absent.
    static func readsBattery() -> Bool {
        var reads = true
        Defaults.ifPresent(key: .accessoryAlertsReadsBattery, assign: &reads)
        return reads
    }
}
