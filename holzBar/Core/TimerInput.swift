//
//  TimerInput.swift
//  holzBar
//

import Foundation

/// The ways a person types the length of a timer, and the presets the Timers tab offers.
///
/// ``parseLength(_:)`` reads whole seconds from a few plain forms and refuses everything else.
/// The text is trimmed and read in lower case; every number is whole and has one to six
/// digits, so no input can overflow. The forms:
///
/// - digits only are minutes: `25` is 25 minutes, `90` is 90 minutes;
/// - two parts with a colon are minutes and seconds, the seconds 0 to 59: `1:30` is 90 seconds;
/// - three parts with colons are hours, minutes and seconds, minutes and seconds 0 to 59:
///   `1:30:00` is an hour and a half;
/// - numbers with units, in any order, each unit at most once, spaces allowed: hours `h`, `hr`,
///   `hrs`, `hour`, `hours`; minutes `m`, `min`, `mins`, `minute`, `minutes`; seconds `s`, `sec`,
///   `secs`, `second`, `seconds`: `1h30m`, `2m 30s`, `45 s`, `1 hour 5 minutes`.
///
/// Empty text, zero, negative numbers, decimals, an unknown unit, a unit twice, a number
/// without a unit among units, a lone colon, more than three parts and a total outside
/// ``TimerBoard/minimumLength`` ... ``TimerBoard/maximumLength`` are refused with `nil`.
nonisolated enum TimerInput {
    /// The lengths of the preset buttons, in seconds, in the order they are shown: 1, 5, 10 and
    /// 25 minutes, and 1 hour.
    static let presets: [Double] = [60, 300, 600, 1_500, 3_600]

    /// The most digits of one number.
    private static let maximumDigits = 6

    /// The length a text describes, in whole seconds, or `nil` when it is not one of the forms
    /// above or lies outside the board's limits.
    static func parseLength(_ text: String) -> Double? {
        let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
        guard !bytes.isEmpty else {
            return nil
        }
        let total: Int?
        if bytes.contains(UInt8(ascii: ":")) {
            total = clockTotal(bytes)
        } else if bytes.allSatisfy(isDigit) {
            total = number(bytes).map { $0 * 60 }
        } else {
            total = unitsTotal(bytes)
        }
        guard
            let total,
            total >= Int(TimerBoard.minimumLength),
            total <= Int(TimerBoard.maximumLength)
        else {
            return nil
        }
        return Double(total)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    /// A whole number of one to six digits, or `nil`.
    private static func number(_ digits: some Collection<UInt8>) -> Int? {
        guard !digits.isEmpty, digits.count <= maximumDigits, digits.allSatisfy(isDigit) else {
            return nil
        }
        return digits.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
    }

    /// `m:ss` and `h:mm:ss`.
    private static func clockTotal(_ bytes: [UInt8]) -> Int? {
        let parts = bytes.split(separator: UInt8(ascii: ":"), omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else {
            return nil
        }
        let values = parts.map { number($0) }
        guard values.allSatisfy({ $0 != nil }) else {
            return nil
        }
        let numbers = values.compactMap { $0 }
        if numbers.count == 2 {
            guard numbers[1] < 60 else {
                return nil
            }
            return numbers[0] * 60 + numbers[1]
        }
        guard numbers[1] < 60, numbers[2] < 60 else {
            return nil
        }
        return numbers[0] * 3_600 + numbers[1] * 60 + numbers[2]
    }

    /// Numbers with units, such as `1h30m` or `2 min 30 s`.
    private static func unitsTotal(_ bytes: [UInt8]) -> Int? {
        var total = 0
        var seen = Set<Character>()
        var index = 0
        func skipSpaces() {
            while index < bytes.count, bytes[index] == UInt8(ascii: " ") {
                index += 1
            }
        }
        skipSpaces()
        while index < bytes.count {
            let digitsStart = index
            while index < bytes.count, isDigit(bytes[index]) {
                index += 1
            }
            guard let value = number(bytes[digitsStart..<index]) else {
                return nil
            }
            skipSpaces()
            let unitStart = index
            while index < bytes.count, isLetter(bytes[index]) {
                index += 1
            }
            guard
                let name = String(bytes: bytes[unitStart..<index], encoding: .utf8),
                let unit = unit(name),
                seen.insert(unit.key).inserted
            else {
                return nil
            }
            total += value * unit.seconds
            skipSpaces()
        }
        return seen.isEmpty ? nil : total
    }

    /// The seconds in a unit and the letter that stands for it, or `nil` for an unknown unit.
    private static func unit(_ name: String) -> (key: Character, seconds: Int)? {
        switch name {
        case "h", "hr", "hrs", "hour", "hours": ("h", 3_600)
        case "m", "min", "mins", "minute", "minutes": ("m", 60)
        case "s", "sec", "secs", "second", "seconds": ("s", 1)
        default: nil
        }
    }
}
