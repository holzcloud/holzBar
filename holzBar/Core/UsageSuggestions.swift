//
//  UsageSuggestions.swift
//  holzBar
//

import Foundation

/// The counters behind the usage suggestions: for each menu bar item, how many times the user
/// opened it on each of the last days. Nothing else is kept: no time of day, no order, no
/// duration and no title. The counters live in one file on this Mac and in no export.
nonisolated struct UsageCounters: Codable, Equatable, Sendable {
    /// How many days of counts are kept.
    static let retentionDays = 30

    /// The counts of each item, by identity key, then by day number.
    private(set) var counts = [String: [Int: Int]]()

    /// The day the counters started, when the user turned the feature on.
    var startDay: Int?

    /// The items whose suggestion the user dismissed.
    var dismissed = Set<String>()

    init(startDay: Int? = nil) {
        self.startDay = startDay
    }

    /// A day number: whole days since 1 January 1970 in the Mac's calendar day, so a change of
    /// time zone moves a click by at most a day and never corrupts the counts.
    static func dayNumber(for date: Date, timeZone: TimeZone = .current) -> Int {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }

    /// Counts one open of an item on a day.
    mutating func record(key: String, day: Int) {
        counts[key, default: [:]][day, default: 0] += 1
        if startDay == nil {
            startDay = day
        }
    }

    /// Drops the days older than the retention, and items with no days left.
    mutating func prune(today: Int) {
        let oldest = today - Self.retentionDays + 1
        for (key, days) in counts {
            let kept = days.filter { $0.key >= oldest }
            counts[key] = kept.isEmpty ? nil : kept
        }
    }

    /// The opens of an item on the last `days` days, today included.
    func clicks(of key: String, inLast days: Int, today: Int) -> Int {
        let oldest = today - days + 1
        return (counts[key] ?? [:]).filter { $0.key >= oldest && $0.key <= today }.values.reduce(0, +)
    }

    /// What is held, for the settings row: the number of items, and of opens.
    var summary: (items: Int, clicks: Int) {
        (counts.count, counts.values.flatMap(\.values).reduce(0, +))
    }

    /// The counts of one item for the last days, oldest first, for the list of what is stored.
    func dailyCounts(of key: String, today: Int) -> [Int] {
        let days = counts[key] ?? [:]
        return (0..<Self.retentionDays).map { offset in
            days[today - Self.retentionDays + 1 + offset] ?? 0
        }
    }

    /// The keys of the items that have counts.
    var keys: [String] {
        counts.keys.sorted()
    }

    /// Forgets everything, including what was dismissed and the start.
    mutating func forgetEverything() {
        self = UsageCounters()
    }
}

nonisolated enum UsageSuggester {
    /// The days the counters must have run before anything is suggested.
    static let observationDays = 14

    /// The days without an open after which an item is suggested.
    static let silentDays = 14

    /// The items to suggest hiding: visible ones that were not opened for ``silentDays`` days,
    /// once the counters have run for ``observationDays`` days.
    ///
    /// - Parameters:
    ///   - visibleKeys: The identity keys of the items in the visible section, in order.
    ///   - excluded: Keys that are never suggested: items that show a live value or that
    ///     are essential, and items a rule controls.
    ///   - today: The day number of today.
    static func suggestions(
        from counters: UsageCounters,
        visibleKeys: [String],
        excluded: Set<String>,
        today: Int
    ) -> [String] {
        guard let start = counters.startDay, today - start >= observationDays else {
            return []
        }
        return visibleKeys.filter { key in
            !excluded.contains(key)
                && !counters.dismissed.contains(key)
                && counters.clicks(of: key, inLast: silentDays, today: today) == 0
        }
    }
}
