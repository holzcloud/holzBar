//
//  ReadoutTiles.swift
//  holzBar
//

import Foundation

/// The readout tiles of the System readouts module, in the order the hub shows them (D-04). The
/// raw values are stored in the settings (`ReadoutTiles`): new cases are appended and the
/// existing ones never change.
nonisolated enum ReadoutTileKind: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case network
    case disk
    case battery
}

/// Which tiles the user switched on, as one stored allow-list (51 P-04).
///
/// An absent list means every tile is on, so a tile a later version adds is on for everyone who
/// never chose. The list also holds ``thermalID``, the thermal state line under the CPU tile. A
/// value from the defaults or from an imported settings file can be anything, so every stored
/// list goes through ``sanitized(_:)``.
nonisolated enum ReadoutTileChoice {
    /// The id of the thermal state line under the CPU tile (D-04, D-17).
    static let thermalID = "thermal"

    /// Every id a stored list may hold, in the order the settings show them: the tiles, then the
    /// thermal state line.
    static let knownIDs: [String] = ReadoutTileKind.allCases.map(\.rawValue) + [thermalID]

    /// How many entries of a stored list are looked at.
    static let maximumChecked = 16

    /// The known ids of a stored list, each once, in the order of ``knownIDs``. Only the first
    /// ``maximumChecked`` entries are looked at. An empty list stays empty: every tile is off.
    static func sanitized(_ ids: [String]) -> [String] {
        let checked = Set(ids.prefix(maximumChecked))
        return knownIDs.filter { checked.contains($0) }
    }

    /// Whether the tile or the thermal line with this id is on. With nothing stored, every one is.
    static func isOn(_ id: String, stored: [String]?) -> Bool {
        guard let stored else {
            return true
        }
        return stored.contains(id)
    }

    /// The list to store after switching one id on or off: with nothing stored, a switch-off
    /// stores every known id but that one. The result is `nil`, storing nothing, when every id is
    /// on again, so a tile added later stays on for this user. An unknown id changes nothing.
    static func setting(_ id: String, on: Bool, stored: [String]?) -> [String]? {
        guard knownIDs.contains(id) else {
            return stored
        }
        var chosen = Set(stored ?? knownIDs)
        if on {
            chosen.insert(id)
        } else {
            chosen.remove(id)
        }
        let list = knownIDs.filter { chosen.contains($0) }
        return list.count == knownIDs.count ? nil : list
    }
}

/// How often the tiles read CPU, GPU, memory and network while the hub is open (D-19).
nonisolated enum ReadoutTileRefresh {
    /// The seconds the settings offer, ascending.
    static let choices = [2, 5, 10, 30]

    /// The seconds used when nothing is stored.
    static let defaultSeconds = 2

    /// The offered choice nearest to a stored value; the shorter one on a tie, ``defaultSeconds``
    /// for none. A value from the defaults can be anything.
    static func snapped(_ seconds: Int?) -> Int {
        guard let seconds else {
            return defaultSeconds
        }
        // Kept in a small range first, so the distances cannot overflow.
        let value = min(max(seconds, 0), 1_000)
        return choices.min { abs($0 - value) < abs($1 - value) } ?? defaultSeconds
    }
}
