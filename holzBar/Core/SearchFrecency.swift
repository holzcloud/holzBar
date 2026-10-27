//
//  SearchFrecency.swift
//  holzBar
//

import Foundation

/// How much the search favours what the user opened from it: often and lately.
///
/// Each open counts one on its day and counts for less every day after, half as much after
/// a week (``halfLifeDays``). The sum is the item's frecency. It turns into a bonus on the
/// match score that grows quickly at first and then levels off at ``maxBonus``, so a favourite
/// beats a slightly better match but a poor match never beats a good one.
nonisolated enum SearchFrecency {
    /// The days after which an open counts half as much.
    static let halfLifeDays = 7.0

    /// The most a favourite can add to a match score. A matched letter scores 16, a match at
    /// the start of the name 24 more.
    static let maxBonus = 40.0

    /// The frecency at which the bonus is half of ``maxBonus``.
    static let halfBonusAt = 3.0

    /// How much an open counts after the given number of days.
    static func weight(ageInDays: Int) -> Double {
        pow(0.5, Double(max(ageInDays, 0)) / halfLifeDays)
    }

    /// The frecency of the counts of one item, by day number.
    static func score(counts: [Int: Int], today: Int) -> Double {
        counts.reduce(0.0) { sum, entry in
            sum + Double(entry.value) * weight(ageInDays: today - entry.key)
        }
    }

    /// The bonus a frecency adds to a match score: 0 for none, below ``maxBonus`` always.
    static func bonus(forScore score: Double) -> Int {
        guard score > 0 else {
            return 0
        }
        return Int((maxBonus * score / (score + halfBonusAt)).rounded())
    }
}

nonisolated extension UsageCounters {
    /// The frecency of an item.
    func frecency(of key: String, today: Int) -> Double {
        SearchFrecency.score(counts: counts[key] ?? [:], today: today)
    }
}
