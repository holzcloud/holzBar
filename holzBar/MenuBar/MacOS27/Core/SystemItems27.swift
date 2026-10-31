//
//  SystemItems27.swift
//  holzBar
//

import Foundation

/// The system items of macOS 27 the user can hide: the ones that draw something.
///
/// The raw values are stored in the defaults and never change. The numbers are the ones
/// measured on macOS 27.0.
nonisolated enum SystemItem27: String, CaseIterable, Sendable {
    case battery
    case clock
    case wifi
    case controlCentre

    /// MenuBarAgent's number of the item.
    var number: Int {
        switch self {
        case .battery: 0
        case .clock: 2
        case .wifi: 6
        case .controlCentre: 8
        }
    }

    /// The Accessibility identifier MenuBarAgent gives the item (measured on macOS 27.2).
    var accessibilityIdentifier: String {
        switch self {
        case .battery: "com.apple.menuextra.battery"
        case .clock: "com.apple.menuextra.clock"
        case .wifi: "com.apple.menuextra.wifi"
        case .controlCentre: "com.apple.menuextra.controlcenter"
        }
    }

    /// The SF Symbol of the item's tile in the holzBar Shelf, which has no picture of a
    /// concealed item.
    var symbolName: String {
        switch self {
        case .battery: "battery.100"
        case .clock: "clock"
        case .wifi: "wifi"
        case .controlCentre: "switch.2"
        }
    }
}

/// MenuBarAgent's numbered system items on macOS 27.
///
/// Measured with `Scripts/macos27/system-item-probe.swift` on macOS 27.0 (2026-09-29).
nonisolated enum SystemItems27 {
    /// The numbers that draw an item on macOS 27.0: 0 is the battery, 2 the clock,
    /// 6 Wi-Fi and 8 Control Centre.
    static let drawn: Set<Int> = [0, 2, 6, 8]

    /// The highest number measured: MenuBarAgent accepted every number from 0 to this one,
    /// offered one at a time and all together in one live assertion.
    static let highestMeasured = 127

    /// The numbers holzBar keeps on the bar unless the user hid them: all measured ones, so a
    /// system item that a later build numbers above 8 stays visible. holzBar hides applications'
    /// items, and the system items only when the user asks (``SystemItem27``).
    static let allowed: ClosedRange<Int> = 0...highestMeasured

    /// The start of the key that stands for a hidden system item in a set of concealed
    /// applications. It holds a colon, which no bundle identifier can, so it never matches an
    /// application.
    static let concealedKeyPrefix = "system-item:"

    /// The key of a hidden system item in a set of concealed applications.
    static func concealedKey(for item: SystemItem27) -> String {
        concealedKeyPrefix + String(item.number)
    }

    /// The numbers an assertion keeps on the bar: every allowed number except the ones of the
    /// hidden system items among the given concealed keys. A key of any other number, a
    /// malformed key and a bundle identifier leave nothing out, so only the four measured
    /// numbers can ever be hidden.
    static func allowedNumbers(concealing concealed: Set<String>) -> [Int] {
        let hidden = Set(SystemItem27.allCases.filter { concealed.contains(concealedKey(for: $0)) }.map(\.number))
        return allowed.filter { !hidden.contains($0) }
    }

    /// The system items named by stored names. Unknown and wrongly cased names are ignored and
    /// duplicates collapse.
    static func hidden(fromStored names: [String]) -> Set<SystemItem27> {
        Set(names.compactMap(SystemItem27.init(rawValue:)))
    }

    /// The names to store for the given items, ordered by number.
    static func storedNames(of items: Set<SystemItem27>) -> [String] {
        items.sorted { $0.number < $1.number }.map(\.rawValue)
    }

    /// The items to hide now: the stored ones while the module is on, none while it is off.
    /// The holzBar Shelf does not matter: it shows a tile for each hidden item.
    static func concealed(stored: Set<SystemItem27>, moduleIsOn: Bool) -> Set<SystemItem27> {
        moduleIsOn ? stored : []
    }

    /// The items in the order the bar draws them from left to right: the battery, Wi-Fi,
    /// Control Center, the clock.
    static func inBarOrder(_ items: Set<SystemItem27>) -> [SystemItem27] {
        let order: [SystemItem27] = [.battery, .wifi, .controlCentre, .clock]
        return order.filter(items.contains)
    }

    /// The system item a concealed key stands for, or `nil` for any other key.
    static func item(forConcealedKey key: String) -> SystemItem27? {
        SystemItem27.allCases.first { concealedKey(for: $0) == key }
    }

    /// The layout entries that conceal the given items while the hidden section is hidden.
    static func layoutEntries(for items: Set<SystemItem27>) -> [String: MacOS27Section] {
        Dictionary(uniqueKeysWithValues: items.map { (concealedKey(for: $0), MacOS27Section.hidden) })
    }
}
