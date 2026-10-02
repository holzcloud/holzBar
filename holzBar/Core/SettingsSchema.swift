//
//  SettingsSchema.swift
//  holzBar
//

import Foundation

/// Checks settings that come from outside the app (a settings file, the iCloud Drive
/// file or Ice's defaults) before holzBar writes them.
///
/// Only keys holzBar stores (`Defaults.Key`) are applied, and only with a value of the
/// kind each key holds, so a crafted file cannot set a key that the app or AppKit reads
/// for something else, nor give a setting a value its reader does not expect.
enum SettingsSchema {
    /// The kind of value a setting holds, as it appears in a property list.
    enum Kind: Sendable {
        /// A Boolean (`CFBoolean`).
        case bool
        /// An integer or floating-point number that is not a Boolean.
        case number
        /// A string.
        case string
        /// Raw data, such as an encoded configuration.
        case data
        /// A date.
        case date
        /// An array whose elements are all strings.
        case stringArray
        /// A dictionary with string keys. Its readers check the contents.
        case dictionary
    }

    /// Returns a Boolean value that indicates whether `value` is of the given kind.
    ///
    /// Property lists decode Booleans as `CFBoolean` and numbers as `CFNumber`, which
    /// both bridge to `NSNumber`; the type identifier tells them apart.
    static func matches(_ value: Any, _ kind: Kind) -> Bool {
        let isBoolean = CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID()
        switch kind {
        case .bool:
            return isBoolean
        case .number:
            return !isBoolean && value is NSNumber
        case .string:
            return value is String
        case .data:
            return value is Data
        case .date:
            return value is Date
        case .stringArray:
            return value is [String]
        case .dictionary:
            return value is [String: Any]
        }
    }

    /// Splits `settings` into the values that may be applied and the keys that are ignored.
    ///
    /// - Parameters:
    ///   - settings: The settings read from outside the app.
    ///   - kinds: The keys that may be set, with the kind of value each one takes.
    /// - Returns: The settings whose key is in `kinds` and whose value has that key's kind,
    ///   and the other keys, sorted.
    static func validated(_ settings: [String: Any], kinds: [String: Kind]) -> (accepted: [String: Any], ignored: [String]) {
        var accepted = [String: Any]()
        var ignored = [String]()
        for (key, value) in settings {
            if let kind = kinds[key], matches(value, kind) {
                accepted[key] = value
            } else {
                ignored.append(key)
            }
        }
        return (accepted, ignored.sorted())
    }
}
