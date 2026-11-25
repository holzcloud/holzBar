//
//  ConnectedDeviceList.swift
//  holzBar
//

import Foundation

/// One line of the connected-devices list: a device by its name, with its level when it has one.
///
/// The `id` is the name key (see ``ConnectedDeviceList/key(for:)``), the one identity of a
/// displayed device. The name is personal (people name their AirPods after themselves), so a row
/// lives in memory only and is never stored, logged or exported.
nonisolated struct ConnectedDeviceRow: Equatable, Sendable, Identifiable {
    /// The name key.
    let id: String
    /// The name as the first device (or, without a device, the first battery) reports it.
    let name: String
    /// The SF Symbol of the device.
    let symbol: String
    /// Whether the device is connected now. A paired device that is not connected is a grey row.
    let isConnected: Bool
    /// The charge in percent, the lowest of the device's parts; `nil` without a level and for a
    /// device that is not connected.
    let percent: Int?
    /// Every part's level, ascending, when there are two or more (AirPods report one per part);
    /// empty otherwise.
    let parts: [Int]
}

/// The accessory with the lowest charge, for the Lowest Device Battery widget.
nonisolated struct LowestDeviceBattery: Equatable, Sendable {
    let name: String
    let percent: Int
    let symbol: String
}

/// The one rule that joins the paired Bluetooth devices with the accessory batteries into the
/// rows of the connected-devices list, in Settings and in the hub's Accessories tab.
///
/// It replaces the join that was in `AccessoryAlertsBodyView`, which matched a battery to a
/// device only when exactly one of each had the same name. The two lists share no identifier, so
/// the name is the key: names are grouped trimmed and compared case- and diacritic-insensitively,
/// one row per name, at the lowest level of the name's batteries. A name that has a battery and
/// no connected device counts as connected, because macOS lists an accessory's power source only
/// while the accessory is connected; a paired device whose name has no battery and no connected
/// device is a grey row. Two different devices with an identical name merge into one row.
nonisolated enum ConnectedDeviceList {
    /// The most rows; connected rows come first, so a grey row is cut before a connected one.
    static let maximumRows = 20

    /// The symbol of a device that has no better one.
    static let unknownSymbol = "dot.radiowaves.left.and.right"

    /// Every symbol the list or the widget can show, in the order a picker would offer them.
    static let widgetSymbols = [
        "airpods",
        "airpodspro",
        "headphones",
        "speaker.wave.2",
        "keyboard",
        "computermouse",
        "battery.25percent",
        unknownSymbol,
    ]

    private static let batterySymbol = "battery.25percent"

    /// The key of a name: trimmed, case and diacritics folded. Swift's string equality already
    /// treats canonically equivalent forms as one.
    static func key(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The symbol for an accessory known only by its battery: the AirPods symbols for a name that
    /// says so, else the one of the category macOS reports, else a plain battery.
    static func symbol(forBatteryNamed name: String, category: String?) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods pro") {
            return "airpodspro"
        }
        if lowered.contains("airpods") {
            return "airpods"
        }
        switch category {
        case "Keyboard": return "keyboard"
        case "Mouse", "Trackpad": return "computermouse"
        case "Headset", "Headphones": return "headphones"
        default: return batterySymbol
        }
    }

    /// The rows of the list.
    ///
    /// - Parameters:
    ///   - connected: The paired devices that are connected now.
    ///   - disconnected: The paired devices that are not.
    ///   - batteries: The accessories that report a level now.
    /// - Returns: Connected rows by name in the Finder's order (ties by key), then grey rows by
    ///   name, at most ``maximumRows``.
    static func rows(
        connected: [AccessoryDevice],
        disconnected: [AccessoryDevice],
        batteries: [AccessoryBattery]
    ) -> [ConnectedDeviceRow] {
        var devicesByKey = [String: AccessoryDevice]()
        for device in connected where devicesByKey[key(for: device.name)] == nil {
            devicesByKey[key(for: device.name)] = device
        }
        var batteriesByKey = [String: [AccessoryBattery]]()
        for battery in batteries {
            batteriesByKey[key(for: battery.name), default: []].append(battery)
        }

        var live = [ConnectedDeviceRow]()
        for rowKey in Set(devicesByKey.keys).union(batteriesByKey.keys) {
            live.append(liveRow(key: rowKey, device: devicesByKey[rowKey], batteries: batteriesByKey[rowKey] ?? []))
        }
        live.sort(by: isOrdered)

        var greyByKey = [String: AccessoryDevice]()
        for device in disconnected {
            let rowKey = key(for: device.name)
            if devicesByKey[rowKey] == nil, batteriesByKey[rowKey] == nil, greyByKey[rowKey] == nil {
                greyByKey[rowKey] = device
            }
        }
        let grey = greyByKey.map { rowKey, device in
            ConnectedDeviceRow(
                id: rowKey,
                name: device.name,
                symbol: device.symbolName,
                isConnected: false,
                percent: nil,
                parts: []
            )
        }
        .sorted(by: isOrdered)

        return Array((live + grey).prefix(maximumRows))
    }

    /// The accessory with the lowest charge, or `nil` without a battery. A tie goes to the name
    /// first in the Finder's order, then to the id.
    static func lowest(_ batteries: [AccessoryBattery]) -> LowestDeviceBattery? {
        let best = batteries.min { lhs, rhs in
            if lhs.percent != rhs.percent {
                return lhs.percent < rhs.percent
            }
            return isOrdered((lhs.name, lhs.id), (rhs.name, rhs.id))
        }
        return best.map {
            LowestDeviceBattery(
                name: $0.name,
                percent: $0.percent,
                symbol: symbol(forBatteryNamed: $0.name, category: $0.category)
            )
        }
    }

    // MARK: Building

    private static func liveRow(key: String, device: AccessoryDevice?, batteries: [AccessoryBattery]) -> ConnectedDeviceRow {
        let levels = batteries.map(\.percent).sorted()
        let first = batteries.first
        let batterySymbol = first.map { symbol(forBatteryNamed: $0.name, category: $0.category) }
        var symbol = device?.symbolName ?? batterySymbol ?? unknownSymbol
        // A device of an unknown kind takes the finer symbol of its battery.
        if symbol == unknownSymbol, let batterySymbol {
            symbol = batterySymbol
        }
        return ConnectedDeviceRow(
            id: key,
            name: device?.name ?? first?.name ?? key,
            symbol: symbol,
            isConnected: true,
            percent: levels.first,
            parts: levels.count >= 2 ? levels : []
        )
    }

    private static func isOrdered(_ lhs: ConnectedDeviceRow, _ rhs: ConnectedDeviceRow) -> Bool {
        isOrdered((lhs.name, lhs.id), (rhs.name, rhs.id))
    }

    private static func isOrdered(_ lhs: (name: String, id: String), _ rhs: (name: String, id: String)) -> Bool {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id < rhs.id
        }
    }
}
