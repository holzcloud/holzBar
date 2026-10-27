//
//  ShelfFind.swift
//  holzBar
//

import Foundation

/// What the user typed to find an item in the holzBar Shelf, and how the highlight moves
/// among the matches.
///
/// Only printable characters are taken: Return, Escape, the arrows and the other function keys
/// are the Shelf's own, and a key with Command or Control is a shortcut, not text. Spaces are
/// not typed either: the search ignores them, and Space opens the highlighted item.
nonisolated struct ShelfFind: Equatable, Sendable {
    /// The longest query: more says nothing a name needs.
    static let maximumLength = 40

    /// What was typed.
    private(set) var query = ""

    /// Whether anything is typed, so the Shelf is searching.
    var isActive: Bool {
        !query.isEmpty
    }

    init() { }

    /// Takes the characters of a key press into the query.
    ///
    /// - Returns: Whether the query changed.
    @discardableResult
    mutating func type(_ characters: String) -> Bool {
        var changed = false
        for character in characters where Self.isTypable(character) && query.count < Self.maximumLength {
            query.append(character)
            changed = true
        }
        return changed
    }

    /// Removes the last character.
    ///
    /// - Returns: Whether the query changed.
    @discardableResult
    mutating func deleteLast() -> Bool {
        guard !query.isEmpty else {
            return false
        }
        query.removeLast()
        return true
    }

    /// Clears the query.
    mutating func clear() {
        query = ""
    }

    /// Whether a character is text a name can contain: not a control character, not a space,
    /// and not one of the private-use characters AppKit gives to the arrows and function keys.
    static func isTypable(_ character: Character) -> Bool {
        guard !character.isWhitespace, !character.isNewline else {
            return false
        }
        return character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0..<0x20, 0x7F..<0xA0, 0xE000...0xF8FF: false
            default: true
            }
        }
    }

    /// The identifier the highlight moves to when it steps through the matches.
    ///
    /// - Parameters:
    ///   - current: The highlighted tile, if any.
    ///   - offset: `1` for the next match and `-1` for the one before; the ends do not wrap.
    ///   - matches: The identifiers of the matches, best first.
    /// - Returns: The first match when nothing in `matches` is highlighted; the highlight
    ///   itself when `matches` is empty or it is at an end.
    static func step(from current: String?, by offset: Int, in matches: [String]) -> String? {
        guard !matches.isEmpty else {
            return current
        }
        guard let current, let index = matches.firstIndex(of: current) else {
            return matches.first
        }
        let target = index + offset
        return matches.indices.contains(target) ? matches[target] : current
    }
}
