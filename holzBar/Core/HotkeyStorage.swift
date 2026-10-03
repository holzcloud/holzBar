//
//  HotkeyStorage.swift
//  holzBar
//

import Foundation

/// How holzBar identifies and stores its hotkeys.
///
/// The `Hotkeys` setting maps each hotkey action's raw value to its key combination,
/// stored as the JSON array `[key, modifiers]` (what `KeyCombination` encodes). Ice stored
/// them the same way, so imported and synced hotkeys keep working.
enum HotkeyStorage {
    /// The signature of holzBar's hotkey events.
    ///
    /// Identical to Ice's, so hotkeys registered by either app are told apart from those of
    /// other apps in the same way. Never change it.
    static let signature: UInt32 = 1231250720

    /// Returns the stored form of a key combination: the JSON array `[key, modifiers]`.
    static func encode(key: Int, modifiers: Int) -> Data {
        (try? JSONEncoder().encode([key, modifiers])) ?? Data()
    }

    /// Reads a stored key combination.
    ///
    /// - Returns: The key code and modifier flags, or `nil` when the data is not a JSON
    ///   array of exactly two integers.
    static func decode(_ data: Data) -> (key: Int, modifiers: Int)? {
        guard
            let values = try? JSONDecoder().decode([Int].self, from: data),
            values.count == 2
        else {
            return nil
        }
        return (values[0], values[1])
    }
}
