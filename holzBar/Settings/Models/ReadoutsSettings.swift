//
//  ReadoutsSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the System readouts module's own settings: how the network speed counts. The unit
/// also serves the Network Speed widget, so it works while the module is off. It saves itself in
/// its `didSet`.
@MainActor
@Observable
final class ReadoutsSettings {
    /// The identifier of the System readouts module in ``ModuleCatalog``.
    static let moduleID = "system-readouts"

    /// Posted when ``rateUnit`` changes, so the menu bar widgets measure and draw the network
    /// speed again. Observed only while the Widgets module is on.
    static let rateUnitDidChange = Notification.Name("holzBar.ReadoutsRateUnitDidChange")

    /// How the network speed counts: bytes or bits per second. Bytes by default (D-08).
    var rateUnit = ReadoutRateUnit.bytes {
        didSet {
            guard rateUnit != oldValue else {
                return
            }
            Defaults.set(rateUnit.rawValue, forKey: .readoutsRateUnit)
            NotificationCenter.default.post(name: Self.rateUnitDidChange, object: nil)
        }
    }

    /// Loads the stored settings. A stored value that is not a unit is ignored.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .readoutsRateUnit) { (rawValue: Int) in
            if let unit = ReadoutRateUnit(rawValue: rawValue) {
                rateUnit = unit
            }
        }
    }
}
