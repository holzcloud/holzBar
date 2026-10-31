//
//  AccessoryBattery.swift
//  holzBar
//

import Foundation

/// The battery of one accessory (a keyboard, a mouse, headphones) as the accessory power
/// sources report it.
nonisolated struct AccessoryBattery: Equatable, Sendable, Identifiable {
    /// The accessory's identifier, or `"name:"` followed by its name when it reports none.
    /// It has the shape of a UUID and is not a Bluetooth address.
    let id: String
    /// The name the accessory reports, trimmed and cut to ``AccessoryBatteryReading/maximumNameBytes``.
    let name: String
    /// The charge as a whole percentage from 0 to 100.
    let percent: Int
    /// The level at which macOS itself warns, when the accessory reports a plausible one.
    let lowWarnLevel: Int?
    /// The accessory category macOS reports ("Keyboard", "Mouse", "Headset", and so on); kept
    /// as it comes, because later macOS versions may add values.
    let category: String?
}

/// Turns the descriptions of the accessory power sources into batteries.
///
/// The descriptions come from one undocumented call whose result Apple does not specify; this
/// type trusts nothing in them. It accepts only the shapes measured in 45-CONTEXT F4, refuses
/// a Boolean or a string where a number belongs, clamps the percentage, bounds every string
/// and drops everything else.
nonisolated enum AccessoryBatteryReading {
    /// The longest name kept, in UTF-8 bytes.
    static let maximumNameBytes = 80
    /// The longest category and identifier kept, in UTF-8 bytes.
    static let maximumFieldBytes = 80
    /// The most batteries one reading returns.
    static let maximumCount = 20

    private static let typeKey = "Type"
    private static let accessoryType = "Accessory Source"
    private static let nameKey = "Name"
    private static let currentKey = "Current Capacity"
    private static let maximumKey = "Max Capacity"
    private static let lowWarnKey = "Low Warn Level"
    private static let categoryKey = "Accessory Category"
    private static let identifierKey = "Accessory Identifier"
    private static let lowWarnRange = 1...99

    /// The battery one power-source description stands for, or `nil` when it is not a
    /// well-formed accessory source with a name and both capacities.
    static func battery(from description: [String: Any]) -> AccessoryBattery? {
        guard
            description[typeKey] as? String == accessoryType,
            let name = text(description[nameKey], maximumBytes: maximumNameBytes),
            let current = wholeNumber(description[currentKey]),
            let maximum = wholeNumber(description[maximumKey]),
            current >= 0,
            let level = BatteryLevel.percent(current: current, maximum: maximum)
        else {
            return nil
        }
        let identifier = text(description[identifierKey], maximumBytes: maximumFieldBytes)
        let lowWarn = wholeNumber(description[lowWarnKey]).flatMap { lowWarnRange.contains($0) ? $0 : nil }
        return AccessoryBattery(
            id: identifier ?? "name:" + name,
            name: name,
            percent: min(max(level, 0), 100),
            lowWarnLevel: lowWarn,
            category: text(description[categoryKey], maximumBytes: maximumFieldBytes)
        )
    }

    /// The batteries of a list of descriptions: invalid ones skipped, the first of two with the
    /// same id kept, sorted by name and then id, and at most ``maximumCount``.
    static func batteries(from descriptions: [[String: Any]]) -> [AccessoryBattery] {
        var seen = Set<String>()
        var result = [AccessoryBattery]()
        for description in descriptions {
            guard let battery = battery(from: description), seen.insert(battery.id).inserted else {
                continue
            }
            result.append(battery)
        }
        result.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        return Array(result.prefix(maximumCount))
    }

    /// A whole number, never a Boolean, never a string.
    ///
    /// Property lists decode Booleans as `CFBoolean` and numbers as `CFNumber`, which both
    /// bridge to `NSNumber`; the type identifier tells them apart (see `SettingsSchema.matches`).
    private static func wholeNumber(_ value: Any?) -> Int? {
        guard let value, let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, abs(double) < 1e12 else {
            return nil
        }
        return Int(double.rounded(.towardZero))
    }

    /// A trimmed, non-empty string cut to `maximumBytes` of UTF-8 without splitting a character.
    private static func text(_ value: Any?, maximumBytes: Int) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        var result = ""
        var bytes = 0
        for scalar in trimmed.unicodeScalars {
            let size = String(scalar).utf8.count
            guard bytes + size <= maximumBytes else {
                break
            }
            result.unicodeScalars.append(scalar)
            bytes += size
        }
        let cut = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }
}
