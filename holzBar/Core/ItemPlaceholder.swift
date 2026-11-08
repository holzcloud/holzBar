//
//  ItemPlaceholder.swift
//  holzBar
//

import Foundation

/// The rule and the schedule for items that still carry a launch placeholder title.
///
/// An app that has not finished launching shows its item with the generic title `Item-N` and
/// publishes the real title a few seconds later (OneDrive is the known case). Keyed by that
/// placeholder, the item looked new: it was placed by the new-items setting and recorded as known,
/// and the saved section of its real title was never restored. So before macOS 27 an item with a
/// placeholder title whose app started less than ``provisionalPeriod`` ago is provisional: it is
/// not placed by the new-items setting, not recorded as known and not stored in the saved
/// sections (``isProvisional(title:runningFor:)``). A profile still applies to it, a saved section
/// does not: earlier versions saved `Item-N` keys with the section macOS gave the item at launch,
/// and such keys are dropped once their app shows its final items
/// (``stalePlaceholderKeys(stored:current:)``).
///
/// A placeholder title alone is not enough: many apps keep `Item-N` for good, so once the period
/// has passed such an item is placed like any other.
///
/// There is no event for a title change of a status item window, so after an app launch the bar
/// is read again a few more times, only while provisional items remain
/// (``provisionalRecheckDelays``). The delays are chosen so that the last read falls after the
/// period; without it the schedule would end inside the period and a leftover `Item-N` item
/// would wait for an unrelated event. The rule that a placeholder is not a title change is
/// ``ItemIdentity``'s; this file adds the timing.
nonisolated enum ItemPlaceholder {
    /// How long after the start of its app an item with a placeholder title is provisional.
    static let provisionalPeriod: Duration = .seconds(60)

    /// The two reads after an app launch that every launch gets (1.5 s, then 2 s later): the
    /// app may add its items late.
    static let launchRecheckDelays: [Duration] = [.milliseconds(1500), .seconds(2)]

    /// The extra reads after those two, each run only while provisional items remain: 5 s, 15 s
    /// and 30 s later, and 12 s after that. The sum of both lists is 65.5 s, so the last read
    /// comes after ``provisionalPeriod`` and leftover `Item-N` items are placed then; the sum
    /// without the last delay is 53.5 s, inside the period.
    static let provisionalRecheckDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(30), .seconds(12)]

    /// Whether an item is provisional: its title is a placeholder (``ItemIdentity/isPlaceholderTitle(_:)``)
    /// and its app, or holzBar, has run for less than ``provisionalPeriod``.
    ///
    /// - Parameters:
    ///   - title: The title of the item.
    ///   - runningFor: How long the item's app (or holzBar, if it started later) has run.
    static func isProvisional(title: String, runningFor: Duration) -> Bool {
        ItemIdentity.isPlaceholderTitle(title) && runningFor < provisionalPeriod
    }

    /// An item on the bar now, for ``stalePlaceholderKeys(stored:current:)``.
    struct CurrentItem: Sendable {
        let namespace: String
        let key: String
        let isProvisional: Bool
    }

    /// The stored keys of launch placeholders that are stale: `namespace:Item-N` (with an
    /// optional `:<occurrence>`) of an app that is on the bar now, has no provisional item and no
    /// item under that key. Versions up to 1.0.3 saved such keys with the section macOS gave the
    /// item at launch; restoring them moved the item at every login. An app that keeps `Item-N`
    /// for good has its item under that key, and an app that is not on the bar keeps its keys.
    static func stalePlaceholderKeys(stored: some Sequence<String>, current: [CurrentItem]) -> Set<String> {
        let currentKeys = Set(current.map(\.key))
        var settledNamespaces = Set(current.map(\.namespace))
        settledNamespaces.subtract(current.filter(\.isProvisional).map(\.namespace))
        var stale = Set<String>()
        for key in stored where !currentKeys.contains(key) {
            guard let separator = key.firstIndex(of: ":") else {
                continue
            }
            let namespace = String(key[..<separator])
            let title = key[key.index(after: separator)...]
            if settledNamespaces.contains(namespace), title.wholeMatch(of: /Item-[0-9]+(?::[0-9]+)?/) != nil {
                stale.insert(key)
            }
        }
        return stale
    }
}
