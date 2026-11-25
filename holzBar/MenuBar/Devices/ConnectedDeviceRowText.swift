//
//  ConnectedDeviceRowText.swift
//  holzBar
//

import SwiftUI

/// What the two surfaces of the connected-devices list (Settings and the hub's Accessories tab)
/// say about a row, so both say the same: the trailing value, the level's state, the spoken label
/// and the part levels. Names and levels are drawn and spoken, never logged.
extension ConnectedDeviceRow {
    /// How empty the battery is, or `nil` without a level. Colour only repeats what the number
    /// says: a level below 30 % is elevated and below 15 % critical.
    var level: GaugeLevel? {
        percent.map { GaugeLevel.level(forRemaining: Double($0) / 100) }
    }

    /// The trailing value: the level, "Connected" without one, or "Not connected" for a paired
    /// device that is not.
    var valueText: Text {
        if let percent {
            return Text(verbatim: AccessoryBattery.percentText(percent))
        }
        return isConnected ? Text("Connected") : Text("Not connected")
    }

    /// The levels of every part as one list, ascending, or `nil` for a device with one level.
    /// macOS gives no part names, so only the levels are listed.
    var partsList: String? {
        guard parts.count >= 2 else {
            return nil
        }
        return parts.map { AccessoryBattery.percentText($0) }.formatted(.list(type: .and, width: .narrow))
    }

    /// The tooltip: the part levels, or empty for a device with one level.
    var partsHelp: String {
        partsList.map { String(localized: "Parts: \($0)") } ?? ""
    }

    /// What VoiceOver says about the row.
    var spokenLabel: Text {
        switch (percent, isConnected) {
        case let (percent?, true):
            return Text("\(name), connected, battery \(percent) percent")
        case let (percent?, false):
            return Text("\(name), battery \(percent) percent")
        case (nil, true):
            return Text("\(name), connected")
        case (nil, false):
            return Text("\(name), not connected")
        }
    }

    /// The spoken part levels, when there are any.
    var spokenParts: Text? {
        partsList.map { Text("Parts: \($0)") }
    }
}
