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
/// 5. For the closed notch (`forClosedNotch`), an activity whose widening has passed
///    (``LiveActivity/widenedUntil``) is not listed, not compact and not counted: it no longer
///    holds the notch open, and lives on in the full view, which the open hub and the Live
///    activities list read. The leave times of finished activities and the ends of widenings stay
///    in ``Board/nextExpiry`` in both views, so the one wait of the hub still wakes for each.
nonisolated enum HubActivityBoard {
    /// How long a finished activity stays.
    static let finishedHold: TimeInterval = 5

    /// The most activities the tab lists.
    static let maximumListed = 5

    /// What the hub shows.
    nonisolated struct Board: Equatable, Sendable {
        /// The activities the tab lists, in order, at most ``HubActivityBoard/maximumListed``.
        var listed: [LiveActivity]
        /// The top live activity, which the closed hub shows by widening the notch, or `nil` when
        /// nothing is live.
        var compact: LiveActivity?
        /// How many live activities are not the compact one.
        var hiddenCount: Int
        /// The earliest moment after `now` at which the board changes by itself, or `nil`: a finished
        /// activity leaves, or a widening ends (also of an activity the closed view no longer shows).
        var nextExpiry: Date?
    }

    /// The board at a moment.
    ///
    /// - Parameter forClosedNotch: Whether the board is for the widened closed notch: an activity
    ///   whose widening has passed is then left out. The default is the full view, which lists every
    ///   live activity.
    static func board(_ activities: [LiveActivity], now: Date, forClosedNotch: Bool = false) -> Board {
        var byKey = [String: LiveActivity]()
        for activity in activities where !isExpired(activity, now: now) {
            if let existing = byKey[activity.key], existing.startedAt >= activity.startedAt {
                continue
            }
            byKey[activity.key] = activity
        }
        let live = byKey.values.sorted(by: isOrderedBefore)
        let expiries = live.flatMap { activity in
            [
                activity.finishedAt.map { $0.addingTimeInterval(finishedHold) },
                activity.widenedUntil,
            ].compactMap { $0 }
        }
        let shown = forClosedNotch ? live.filter { !hasWidened($0, now: now) } : live
        return Board(
            listed: Array(shown.prefix(maximumListed)),
            compact: shown.first,
            hiddenCount: max(shown.count - 1, 0),
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

    /// Whether an activity's widening of the closed notch is over.
    private static func hasWidened(_ activity: LiveActivity, now: Date) -> Bool {
        guard let until = activity.widenedUntil else {
            return false
        }
        return now >= until
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
