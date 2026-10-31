//
//  AccessoryAlertOptions.swift
//  holzBar
//

import Foundation

/// The switches of the Accessory alerts module: which kinds of event raise an alert.
///
/// Connect alerts are on by default. Disconnect alerts are off, because AirPods in and out of
/// their case disconnect often. The low-battery switches are added to this value later, each
/// with a default.
nonisolated struct AccessoryAlertOptions: Equatable, Sendable {
    /// Whether a device that connects raises an alert.
    var connect: Bool
    /// Whether a device that disconnects raises an alert.
    var disconnect: Bool

    /// The options of a user who changed nothing.
    static let `default` = AccessoryAlertOptions(connect: true, disconnect: false)

    /// Whether an event raises an alert.
    func allows(_ event: AccessoryEvent) -> Bool {
        switch event {
        case .connected: connect
        case .disconnected: disconnect
        }
    }
}
