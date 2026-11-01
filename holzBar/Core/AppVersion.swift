//
//  AppVersion.swift
//  holzBar
//

import Foundation

/// A version such as `1.0.1` or `1.0.1-beta1`, ordered the way semantic versioning orders it.
///
/// A prerelease sorts before the same version without one (`1.0.1-beta1 < 1.0.1`), and
/// numbers inside it compare as numbers (`beta2 < beta10`). A missing component is zero, so
/// `1.0` equals `1.0.0`. The only untrusted input is a string read from the defaults, which
/// any process of the user can write, so parsing never traps: it returns `nil` for anything
/// that is not a version, overflowing numbers included.
nonisolated struct AppVersion: Comparable, Hashable, Sendable {
    /// One dot-separated identifier of a prerelease.
    private enum Identifier: Comparable, Hashable, Sendable {
        /// An identifier of digits only, such as the `1` of `beta.1`.
        case number(Int)
        /// Letters, optionally followed by a number, such as `beta10`.
        case text(prefix: String, number: Int?)

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case let (.number(left), .number(right)):
                left < right
            case (.number, .text):
                true
            case (.text, .number):
                false
            case let (.text(leftPrefix, leftNumber), .text(rightPrefix, rightNumber)):
                if leftPrefix != rightPrefix {
                    leftPrefix < rightPrefix
                } else {
                    switch (leftNumber, rightNumber) {
                    case let (left?, right?): left < right
                    case (nil, _?): true
                    default: false
                    }
                }
            }
        }
    }

    /// The most numeric components a version has.
    private static let componentCount = 4

    /// The numeric components, padded with zeros to four.
    private let components: [Int]
    private let prerelease: [Identifier]
    /// The numeric part as it was written.
    private let coreText: String
    private let text: String

    /// The version `string` names, or `nil` when it is not one.
    ///
    /// The text is one to four numbers separated by single dots, optionally followed by a
    /// hyphen and dot-separated identifiers of ASCII letters and digits. Nothing is trimmed.
    init?(_ string: String) {
        let parts = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let numeric = parts.first, !numeric.isEmpty else {
            return nil
        }
        let numbers = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count <= Self.componentCount else {
            return nil
        }
        var components: [Int] = []
        for number in numbers {
            guard let value = Self.number(from: number) else {
                return nil
            }
            components.append(value)
        }
        var prerelease: [Identifier] = []
        if parts.count == 2 {
            for identifier in parts[1].split(separator: ".", omittingEmptySubsequences: false) {
                guard let parsed = Self.identifier(from: identifier) else {
                    return nil
                }
                prerelease.append(parsed)
            }
        }
        self.components = components + Array(repeating: 0, count: Self.componentCount - components.count)
        self.prerelease = prerelease
        self.coreText = String(numeric)
        self.text = string
    }

    /// The version without its prerelease: `1.0.1` for `1.0.1-beta3`.
    var core: AppVersion {
        // The numeric part of a parsed version always parses again.
        AppVersion(coreText) ?? self
    }

    /// Whether the version has a prerelease part, such as `-beta1`.
    var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    /// The version as it was written.
    var displayString: String {
        text
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(components)
        hasher.combine(prerelease)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.components != rhs.components {
            return lhs.components.lexicographicallyPrecedes(rhs.components)
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, _):
            // No prerelease is the later version, or the same one.
            return false
        case (false, true):
            return true
        case (false, false):
            return lhs.prerelease.lexicographicallyPrecedes(rhs.prerelease)
        }
    }

    // MARK: Parsing

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    /// A non-empty run of ASCII digits as a number; `nil` when it is empty, has any other
    /// character or does not fit an `Int`.
    private static func number(from digits: Substring) -> Int? {
        guard !digits.isEmpty, digits.utf8.allSatisfy(isDigit) else {
            return nil
        }
        return Int(digits)
    }

    private static func identifier(from text: Substring) -> Identifier? {
        guard !text.isEmpty, text.utf8.allSatisfy({ isDigit($0) || isLetter($0) }) else {
            return nil
        }
        if text.utf8.allSatisfy(isDigit) {
            return number(from: text).map(Identifier.number)
        }
        // Letters, then an optional number: `beta10` is `beta` and 10.
        let prefix = text.prefix { !isDigit($0.utf8.first ?? 0) }
        let rest = text.dropFirst(prefix.count)
        if rest.isEmpty {
            return .text(prefix: String(prefix), number: nil)
        }
        if let value = number(from: rest) {
            return .text(prefix: String(prefix), number: value)
        }
        if rest.utf8.allSatisfy(isDigit) {
            // Digits that do not fit an Int.
            return nil
        }
        // Letters after the digits (`b1x2`): compare as plain text.
        return .text(prefix: String(text), number: nil)
    }
}
