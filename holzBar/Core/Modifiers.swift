//
//  Modifiers.swift
//  holzBar
//

import Foundation

/// A bit mask containing the modifier keys for a hotkey.
///
/// The raw values are stored with every hotkey (and read from Ice's settings when
/// they are imported), so they must never change. The conversions to and from the
/// system's modifier flags live in `holzBar/Hotkeys/ModifierFlags.swift`.
struct Modifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let shift = Modifiers(rawValue: 1 << 2)
    static let command = Modifiers(rawValue: 1 << 3)
}

extension Modifiers {
    /// All modifiers in the order displayed by the system,
    /// according to Apple's style guide.
    static let canonicalOrder = [control, option, shift, command]

    /// A symbolic string representation of the modifiers.
    var symbolicValue: String {
        var result = ""
        if contains(.control) {
            result.append("⌃")
        }
        if contains(.option) {
            result.append("⌥")
        }
        if contains(.shift) {
            result.append("⇧")
        }
        if contains(.command) {
            result.append("⌘")
        }
        return result
    }
}

extension Modifiers {
    /// A reason why a combination with these modifiers cannot be used as a hotkey.
    enum Rejection: Equatable {
        /// No modifier: the key alone would fire the hotkey on every press.
        case missing
        /// Shift alone: the hotkey would fire on every capital letter.
        case shiftOnly
        /// Option, or Option and Shift: macOS 15 and later refuse to register these
        /// with `RegisterEventHotKey`, so that a global hotkey cannot read typed text.
        case optionOnly
    }

    /// Returns the reason why a combination with these modifiers cannot be used as
    /// a hotkey, or `nil` when it can.
    ///
    /// - Parameter refusesOptionOnly: Whether the system refuses hotkeys whose only
    ///   modifiers are Option, or Option and Shift. Callers pass `true` on macOS 15
    ///   and later.
    func rejection(refusesOptionOnly: Bool) -> Rejection? {
        switch self {
        case []:
            .missing
        case .shift:
            .shiftOnly
        case .option, [.option, .shift]:
            refusesOptionOnly ? .optionOnly : nil
        default:
            nil
        }
    }
}
