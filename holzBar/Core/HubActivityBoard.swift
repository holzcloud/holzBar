//
//  HubActivityBoard.swift
//  holzBar
//

import Foundation

/// Which live activities the Notch hub shows, as pure decisions.
///
/// The board takes the activities every module returned and the moment it works at, and says
/// what is listed and in what order, which one is the compact one, how many more are live and
/// when the next finished activity leaves. It reads no clock and waits for nothing: the hub
/// arms one wait for ``Board/nextExpiry`` and asks again.
///
/// Rules, in order:
/// 1. An activity that finished ``finishedHold`` seconds ago or longer is dropped; one that
///    finishes in the future counts as running.
/// 2. Of two activities with the same ``LiveActivity/key`` the one that started later stays.
/// 3. The order is the higher priority first, then the newer start, then the key.
/// 4. The first of the order is the compact one; the first ``maximumListed`` are listed; every
///    live activity but the compact one is counted in ``Board/hiddenCount``.
nonisolated enum HubActivityBoard {
    /// How long a finished activity stays.
    static let finishedHold: TimeInterval = 5

    /// The most activities the tab lists.
    static let maximumListed = 5

    /// What the hub shows.
    nonisolated struct Board: Equatable, Sendable {
        /// The activities the tab lists, in order, at most ``HubActivityBoard/maximumListed``.
        var listed: [LiveActivity]
        /// The activity the capsule shows, or `nil` when nothing is live.
        var compact: LiveActivity?
        /// How many live activities are not the compact one.
        var hiddenCount: Int
        /// The earliest moment after `now` at which a finished activity leaves, or `nil`.
        var nextExpiry: Date?
    }

    /// The board at a moment.
    static func board(_ activities: [LiveActivity], now: Date) -> Board {
        var byKey = [String: LiveActivity]()
        for activity in activities where !isExpired(activity, now: now) {
            if let existing = byKey[activity.key], existing.startedAt >= activity.startedAt {
                continue
            }
            byKey[activity.key] = activity
        }
        let live = byKey.values.sorted(by: isOrderedBefore)
        let expiries = live.compactMap { activity in
            activity.finishedAt.map { $0.addingTimeInterval(finishedHold) }
        }
        return Board(
            listed: Array(live.prefix(maximumListed)),
            compact: live.first,
            hiddenCount: max(live.count - 1, 0),
            nextExpiry: expiries.filter { $0 > now }.min()
        )
    }

    /// Whether a finished activity has stayed long enough.
    private static func isExpired(_ activity: LiveActivity, now: Date) -> Bool {
        guard let finishedAt = activity.finishedAt else {
            return false
        }
        return now.timeIntervalSince(finishedAt) >= finishedHold
    }

    private static func isOrderedBefore(_ lhs: LiveActivity, _ rhs: LiveActivity) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.key < rhs.key
    }
}
