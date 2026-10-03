//
//  ItemHints.swift
//  holzBar
//

import Foundation

/// The letters of the item hints: a hotkey shows every menu bar item with a letter, and
/// typing the letter opens that item (THAW-14).
///
/// Letters start on the home row (a s d f j k l g h), then follow the rest of the alphabet.
/// With more items than letters, the last letters become prefixes of two-letter hints, so
/// no hint is the start of another: typing never picks an item too early.
nonisolated enum ItemHints {
    /// The letters in the order they are handed out.
    static let alphabet: [Character] = Array("asdfjklgh") + Array("bceimnopqrtuvwxyz")

    /// What a typed sequence picks.
    nonisolated enum Match: Equatable, Sendable {
        /// The item at this index of the hints.
        case item(Int)
        /// The typed letters start a hint; wait for the next one.
        case pending
        /// No hint starts with the typed letters.
        case none
    }

    /// Unique hints for the given number of items, in item order.
    ///
    /// Single letters come first; two letters only once the single ones run out. At most
    /// 26 × 26 items get a hint.
    static func letters(count: Int) -> [String] {
        let size = alphabet.count
        guard count > 0 else {
            return []
        }
        guard count > size else {
            return alphabet.prefix(count).map { String($0) }
        }
        let count = min(count, size * size)
        // k single letters and (size - k) prefixes of `size` hints each must cover `count`:
        // k + (size - k) × size >= count, with k as large as possible.
        let singles = (size * size - count) / (size - 1)
        var hints = alphabet.prefix(singles).map { String($0) }
        for prefix in alphabet.dropFirst(singles) {
            for letter in alphabet {
                guard hints.count < count else {
                    return hints
                }
                hints.append(String(prefix) + String(letter))
            }
        }
        return hints
    }

    /// What the typed letters pick among the hints.
    static func match(typed: String, hints: [String]) -> Match {
        let typed = typed.lowercased()
        guard !typed.isEmpty else {
            return .pending
        }
        if let index = hints.firstIndex(of: typed) {
            return .item(index)
        }
        if hints.contains(where: { $0.hasPrefix(typed) }) {
            return .pending
        }
        return .none
    }
}
