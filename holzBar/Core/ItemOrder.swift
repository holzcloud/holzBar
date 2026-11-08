//
//  ItemOrder.swift
//  holzBar
//

import Foundation

/// The rules for the order of the items inside their sections before macOS 27.
///
/// The saved sections (`ItemSections`) say where an item belongs, not in which place. The order
/// is saved as one flat list of identity keys, left to right across the whole bar (`ItemOrder`),
/// so a restore can put an item back in its place after an app relaunched, a display was
/// connected or an item came back (Focus, Sound).
///
/// Every move is a synthetic drag that hides the pointer and can fail, so the plan moves as few
/// items as possible: the items that already stand in the right order relative to each other
/// (a longest increasing subsequence) stay, and only the others move (``plan(current:wanted:)``).
/// The plan is pure; the moves, their pace and the guards that bound them are the app's.
nonisolated enum ItemOrder {
    /// The most keys stored.
    static let maximumKeys = 1000

    /// The longest key stored, in UTF-8 bytes.
    static let maximumKeyLength = 512

    /// The most moves one order pass makes.
    static let maximumMovesPerPass = 6

    /// Where a moved item goes, relative to another item of the same section.
    enum Anchor: Equatable, Sendable {
        /// Right of the item with this key.
        case after(String)
        /// Left of the item with this key.
        case before(String)
    }

    /// One move of a plan: the item with ``key`` goes to ``anchor``.
    struct Step: Equatable, Sendable {
        let key: String
        let anchor: Anchor
    }

    // MARK: Stored order

    /// The keys without empty ones, without ones over ``maximumKeyLength`` bytes and without
    /// repeated ones (the first stays), at most ``maximumKeys``. A value from the defaults or
    /// from an imported settings file can be anything.
    static func sanitized(_ keys: [String]) -> [String] {
        Array(valid(keys).prefix(maximumKeys))
    }

    /// The saved order brought up to date with the order on the bar now. The current order wins
    /// for every key that is on the bar; a saved key that is not (its app is not running) is
    /// inserted right after its nearest saved predecessor that is in the result, or first, so it
    /// keeps its place for when it returns. A key the saved order does not know stays where it is.
    ///
    /// Past ``maximumKeys`` the saved keys that are not on the bar go first, last one first; only
    /// then do keys on the bar go, from the right.
    static func merge(saved: [String], current: [String]) -> [String] {
        let savedKeys = valid(saved)
        let currentKeys = valid(current)
        let onBar = Set(currentKeys)
        var result = currentKeys
        var inResult = onBar
        for (index, key) in savedKeys.enumerated() where !inResult.contains(key) {
            let predecessor = savedKeys[..<index].last { inResult.contains($0) }
            if let predecessor, let position = result.firstIndex(of: predecessor) {
                result.insert(key, at: position + 1)
            } else {
                result.insert(key, at: 0)
            }
            inResult.insert(key)
        }
        var excess = result.count - maximumKeys
        if excess > 0 {
            var index = result.count - 1
            while excess > 0 && index >= 0 {
                if !onBar.contains(result[index]) {
                    result.remove(at: index)
                    excess -= 1
                }
                index -= 1
            }
        }
        return Array(result.prefix(maximumKeys))
    }

    private static func valid(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { key in
            !key.isEmpty && key.utf8.count <= maximumKeyLength && seen.insert(key).inserted
        }
    }

    // MARK: Plan

    /// The indices of one longest strictly increasing subsequence of the ranks, in
    /// O(n log n). The same ranks always give the same indices; the empty list gives none.
    static func stableIndices(of ranks: [Int]) -> Set<Int> {
        guard !ranks.isEmpty else {
            return []
        }
        // tails[length - 1] is the index of the smallest last rank of an increasing run of that length.
        var tails = [Int]()
        var previous = [Int?](repeating: nil, count: ranks.count)
        for (index, rank) in ranks.enumerated() {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if ranks[tails[middle]] < rank {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            previous[index] = low > 0 ? tails[low - 1] : nil
            if low == tails.count {
                tails.append(index)
            } else {
                tails[low] = index
            }
        }
        var result = Set<Int>()
        var cursor = tails.last
        while let index = cursor {
            result.insert(index)
            cursor = previous[index]
        }
        return result
    }

    /// The moves that bring the keys of `current` (left to right) into the order of `wanted`,
    /// applied one after the other: only the keys off a longest increasing subsequence move, each
    /// right after its predecessor in `wanted`, or, when it is first in `wanted`, left of the
    /// first key that stays. Keys of `current` that `wanted` does not know never move and keep
    /// their neighbours; keys of `wanted` that are not in `current` are ignored.
    static func plan(current: [String], wanted: [String]) -> [Step] {
        let present = Set(current)
        var seen = Set<String>()
        let order = wanted.filter { present.contains($0) && seen.insert($0).inserted }
        guard order.count > 1 else {
            return []
        }
        let rankByKey = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        var keysInBarOrder = [String]()
        var ranks = [Int]()
        var barSeen = Set<String>()
        for key in current where barSeen.insert(key).inserted {
            if let rank = rankByKey[key] {
                keysInBarOrder.append(key)
                ranks.append(rank)
            }
        }
        let stableKeys = Set(stableIndices(of: ranks).map { keysInBarOrder[$0] })
        guard stableKeys.count < order.count else {
            return []
        }
        let firstStable = keysInBarOrder.first { stableKeys.contains($0) }
        var steps = [Step]()
        for (index, key) in order.enumerated() where !stableKeys.contains(key) {
            if index > 0 {
                steps.append(Step(key: key, anchor: .after(order[index - 1])))
            } else if let firstStable {
                steps.append(Step(key: key, anchor: .before(firstStable)))
            }
        }
        return steps
    }

    // MARK: Reappearing items

    /// The keys on the bar now that were not on the bar in the previous read and have a saved
    /// section: items that come and go (Focus, Sound, an app that was quit and opened again). The
    /// first read after launch has no previous read, so the caller records it without asking.
    static func reappeared(previous: Set<String>, current: [String], saved: Set<String>) -> Set<String> {
        Set(current.filter { !previous.contains($0) && saved.contains($0) })
    }
}
