//
//  HotkeyStorage.swift
//  holzBar
//

import Foundation

/// How holzBar identifies and stores its hotkeys.
///
/// The `Hotkeys` setting maps each hotkey action's raw value to its key combination,
/// stored as the JSON array `[key, modifiers]` (what `KeyCombination` encodes). Ice stored
/// them the same way, so imported hotkeys keep working.
nonisolated enum HotkeyStorage {
    /// The signature of holzBar's hotkey events.
    ///
    /// Identical to Ice's, so hotkeys registered by either app are told apart from those of
    /// other apps in the same way. Never change it.
    static let signature: UInt32 = 1231250720

    /// Returns the stored form of a key combination: the JSON array `[key, modifiers]`.
    static func encode(key: Int, modifiers: Int) -> Data {
        (try? JSONEncoder().encode([key, modifiers])) ?? Data()
    }

    /// The virtual key codes of macOS keyboards.
    static let validKeyCodes = 0...127

    /// The modifier bits holzBar knows (``Modifiers``).
    static let knownModifierBits = Modifiers.canonicalOrder.reduce(0) { $0 | $1.rawValue }

    /// Returns whether a key code and modifier flags can be a hotkey: the key code is a
    /// virtual key code (0 through 127) and the flags hold no bit ``Modifiers`` does not know.
    ///
    /// Anything can write holzBar's preferences, and a value out of range trapped in the
    /// conversions for the system at every launch (jordanbaird/Ice#985).
    static func isValid(key: Int, modifiers: Int) -> Bool {
        validKeyCodes.contains(key) && modifiers & ~knownModifierBits == 0
    }

    /// Reads a stored key combination.
    ///
    /// - Returns: The key code and modifier flags, or `nil` when the data is not a JSON
    ///   array of exactly two integers, or they cannot be a hotkey (``isValid(key:modifiers:)``).
    static func decode(_ data: Data) -> (key: Int, modifiers: Int)? {
        guard
            let values = try? JSONDecoder().decode([Int].self, from: data),
            values.count == 2,
            isValid(key: values[0], modifiers: values[1])
        else {
            return nil
        }
        return (values[0], values[1])
    }

    /// Returns why a stored key combination is not loaded, or `nil` when it is.
    ///
    /// The same rule as the hotkey recorder (`Modifiers.rejection(refusesOptionOnly:)`):
    /// a stored combination with no modifier, or Shift alone, would take that key from
    /// every app, system-wide, on every press. Anything can write holzBar's settings (an
    /// imported file, or any process of the user), so the rule is applied again
    /// when the hotkeys are loaded.
    ///
    /// - Parameter refusesOptionOnly: Whether the system refuses Option-only hotkeys
    ///   (macOS 15 and later).
    static func loadRejection(modifiers: Int, refusesOptionOnly: Bool) -> Modifiers.Rejection? {
        Modifiers(rawValue: modifiers).rejection(refusesOptionOnly: refusesOptionOnly)
    }

    /// Returns the storage keys of the stored hotkeys that are not loaded because a hotkey
    /// loaded before them has the same key combination.
    ///
    /// The system registers a combination only once per app, so the later hotkey never
    /// worked; the first one in load order keeps the combination.
    ///
    /// - Parameter loadOrder: The stored hotkeys in the order they are loaded: the actions,
    ///   then the profiles and items by storage key.
    static func duplicateStorageKeys(inLoadOrder loadOrder: [(storageKey: String, key: Int, modifiers: Int)]) -> Set<String> {
        var used = Set<[Int]>()
        var duplicates = Set<String>()
        for entry in loadOrder where !used.insert([entry.key, entry.modifiers]).inserted {
            duplicates.insert(entry.storageKey)
        }
        return duplicates
    }
}
