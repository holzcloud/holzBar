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
/// for something else, nor give a setting a value its reader does not expect. Numbers are
/// also checked for their value (``NumberRule``): a value such as `1e300`, infinity or NaN
/// would trap where the app turns it into an `Int` or a `Duration`, at every launch.
nonisolated enum SettingsSchema {
    /// The kind of value a setting holds, as it appears in a property list.
    nonisolated enum Kind: Sendable {
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

    /// The values a numeric setting may take.
    nonisolated enum NumberRule: Equatable, Sendable {
        /// A value set with a slider: finite values outside the range are clamped to it.
        case clamped(ClosedRange<Double>)
        /// A whole number, such as the raw value of a choice or a count: values outside the
        /// range or with a fraction are refused.
        case wholeNumber(ClosedRange<Double>)

        /// The range the value is kept in.
        var range: ClosedRange<Double> {
            switch self {
            case .clamped(let range), .wholeNumber(let range):
                range
            }
        }

        /// `value` as the setting may take it, or `nil` when it is refused.
        ///
        /// Infinity and NaN are always refused. A value the rule leaves unchanged is
        /// returned as it is, so an integer stays an integer.
        func sanitized(_ value: NSNumber) -> NSNumber? {
            let double = value.doubleValue
            guard double.isFinite else {
                return nil
            }
            switch self {
            case .clamped(let range):
                if range.contains(double) {
                    return value
                }
                return NSNumber(value: min(max(double, range.lowerBound), range.upperBound))
            case .wholeNumber(let range):
                guard range.contains(double), double.rounded(.towardZero) == double else {
                    return nil
                }
                return value
            }
        }

        /// `value` kept in the rule's range; `fallback` when it is not finite.
        ///
        /// For values read from the defaults, which any process of the user can write.
        func clamp(_ value: Double, fallback: Double) -> Double {
            guard value.isFinite else {
                return fallback
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }
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
    ///   - numberRules: The values numeric keys may take. A number without a rule must
    ///     still be finite.
    /// - Returns: The settings whose key is in `kinds` and whose value has that key's kind
    ///   and passes its rule (clamped where the rule clamps), and the other keys, sorted.
    static func validated(
        _ settings: [String: Any],
        kinds: [String: Kind],
        numberRules: [String: NumberRule] = [:]
    ) -> (accepted: [String: Any], ignored: [String]) {
        var accepted = [String: Any]()
        var ignored = [String]()
        for (key, value) in settings {
            guard let kind = kinds[key], matches(value, kind) else {
                ignored.append(key)
                continue
            }
            guard kind == .number, let number = value as? NSNumber else {
                accepted[key] = value
                continue
            }
            if let rule = numberRules[key] {
                if let sanitized = rule.sanitized(number) {
                    accepted[key] = sanitized
                } else {
                    ignored.append(key)
                }
            } else if number.doubleValue.isFinite {
                accepted[key] = value
            } else {
                ignored.append(key)
            }
        }
        return (accepted, ignored.sorted())
    }
}
