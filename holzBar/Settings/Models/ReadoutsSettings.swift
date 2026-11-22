//
//  ReadoutsSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the System readouts module's own settings: how the network speed counts, which tiles
/// show, whether the CPU tile carries the thermal state line and how often the tiles read. The
/// unit also serves the Network Speed widget, so it works while the module is off. It saves
/// itself in its `didSet`.
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

    /// The ids of the tiles that are on, and "thermal" for the thermal state line; `nil` means
    /// every tile is on, as long as the user has not chosen (D-04). Use ``isOn(_:)`` and
    /// ``setTile(_:on:)``.
    private(set) var enabledTiles: [String]? {
        didSet {
            if let enabledTiles {
                Defaults.set(enabledTiles, forKey: .readoutTiles)
            } else {
                Defaults.removeObject(forKey: .readoutTiles)
            }
        }
    }

    /// How often the tiles read CPU, GPU, memory and network while the hub is open: 2, 5, 10 or
    /// 30 seconds, 2 by default (D-19).
    var tileRefreshSeconds = ReadoutTileRefresh.defaultSeconds {
        didSet {
            guard tileRefreshSeconds != oldValue else {
                return
            }
            Defaults.set(tileRefreshSeconds, forKey: .readoutsTileRefresh)
        }
    }

    /// Whether a tile is on.
    func isOn(_ kind: ReadoutTileKind) -> Bool {
        ReadoutTileChoice.isOn(kind.rawValue, stored: enabledTiles)
    }

    /// Whether the CPU tile carries the thermal state line (D-17).
    var showsThermalLine: Bool {
        ReadoutTileChoice.isOn(ReadoutTileChoice.thermalID, stored: enabledTiles)
    }

    /// Switches a tile on or off. The first switch-off stores every other tile as on.
    func setTile(_ kind: ReadoutTileKind, on: Bool) {
        enabledTiles = ReadoutTileChoice.setting(kind.rawValue, on: on, stored: enabledTiles)
    }

    /// Switches the thermal state line under the CPU tile on or off.
    func setThermalLine(_ on: Bool) {
        enabledTiles = ReadoutTileChoice.setting(ReadoutTileChoice.thermalID, on: on, stored: enabledTiles)
    }

    /// Loads the stored settings. A stored value that is not a unit is ignored, a tile list keeps
    /// only known ids and a refresh snaps to the nearest choice.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .readoutsRateUnit) { (rawValue: Int) in
            if let unit = ReadoutRateUnit(rawValue: rawValue) {
                rateUnit = unit
            }
        }
        Defaults.ifPresent(key: .readoutTiles) { (stored: [String]) in
            enabledTiles = ReadoutTileChoice.sanitized(stored)
        }
        Defaults.ifPresent(key: .readoutsTileRefresh) { (seconds: Int) in
            tileRefreshSeconds = ReadoutTileRefresh.snapped(seconds)
        }
    }
}
