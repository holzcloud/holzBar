//
//  ChangeReveal.swift
//  holzBar
//

import Foundation

/// When a hidden item that changed is shown for a moment (THAW-12).
///
/// The user marks items "Show When It Changes"; Accessibility tells holzBar when such an
/// item's title or value changes. Changes are counted once they have been quiet for
/// ``debounce`` (a counter that ticks several times in a row is one change), an item is
/// shown at most every ``minimumGap``, and nothing is shown in Zen mode or for an item that
/// is visible anyway. An app cannot keep its item on screen by changing it all the time.
///
/// Times are seconds of a monotonic clock, passed in, so the rules can be tested.
nonisolated struct ChangeReveal: Sendable {
    /// How long changes of one item must be quiet before it is shown.
    static let debounce: TimeInterval = 1

    /// The shortest time between two reveals of one item.
    static let minimumGap: TimeInterval = 30

    /// The last change of each item that waits to be shown, by item key.
    private var pending = [String: TimeInterval]()

    /// When each item was last shown, by item key.
    private var lastReveals = [String: TimeInterval]()

    /// Notes a change of an item.
    ///
    /// - Parameters:
    ///   - key: The item's identity key.
    ///   - isZenActive: Whether Zen mode is on, which shows nothing.
    ///   - isVisible: Whether the item is visible anyway.
    ///   - time: When the change happened.
    mutating func noteChange(key: String, isZenActive: Bool, isVisible: Bool, at time: TimeInterval) {
        guard !isZenActive, !isVisible else {
            pending[key] = nil
            return
        }
        if let lastReveal = lastReveals[key], time - lastReveal < Self.minimumGap {
            return
        }
        pending[key] = time
    }

    /// The items to show now, whose changes have been quiet long enough; they count as
    /// shown at `time`.
    mutating func due(at time: TimeInterval) -> [String] {
        var keys = [String]()
        for (key, lastChange) in pending where time - lastChange >= Self.debounce {
            pending[key] = nil
            if let lastReveal = lastReveals[key], time - lastReveal < Self.minimumGap {
                continue
            }
            lastReveals[key] = time
            keys.append(key)
        }
        return keys.sorted()
    }

    /// When the next waiting change will be due, for one bounded wait; `nil` when nothing
    /// waits.
    var nextDueTime: TimeInterval? {
        pending.values.min().map { $0 + Self.debounce }
    }
}
