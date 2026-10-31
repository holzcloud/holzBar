//
//  AccessoryAlertsSettings.swift
//  holzBar
//

import Observation

/// Model for the Accessory alerts module's own settings: whether a connecting accessory and a
/// disconnecting one each raise an alert. Each saves itself in its `didSet`.
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

    /// Loads the stored switches. An absent key, or a value that is not a Boolean, keeps the
    /// default.
    init() {
        let stored = Self.options()
        connect = stored.connect
        disconnect = stored.disconnect
    }

    /// The switches as stored now, with the defaults for what is absent.
    static func options() -> AccessoryAlertOptions {
        var options = AccessoryAlertOptions.default
        Defaults.ifPresent(key: .accessoryAlertsOnConnect, assign: &options.connect)
        Defaults.ifPresent(key: .accessoryAlertsOnDisconnect, assign: &options.disconnect)
        return options
    }
}
