//
//  SearchRanking.swift
//  holzBar
//

import Foundation

/// The order of the menu bar search: the fuzzy match of what was typed (`FuzzyMatch`), the full
/// names of a short name (`SearchSynonyms`) and what the user opened lately (`SearchFrecency`).
nonisolated enum SearchRanking {
    /// What a match through a short name loses against the same score from the typed text.
    static let synonymPenalty = 6

    /// The items that match `query`, best first.
    ///
    /// A match in order always ranks above a misspelling. Among them the order is the match
    /// score plus the frecency bonus; items equal in both keep the one that was opened more
    /// lately first, then their order. An empty query keeps every item and puts the favourites
    /// first (``favouritesFirst(_:frecency:)``).
    ///
    /// - Parameters:
    ///   - items: The items to search.
    ///   - query: What the user typed.
    ///   - key: The text of an item that is searched.
    ///   - frecency: The frecency of an item, 0 when it was never opened from the search.
    static func rank<T>(
        _ items: [T],
        query: String,
        key: (T) -> String,
        frecency: (T) -> Double
    ) -> [T] {
        guard query.contains(where: { !$0.isWhitespace }) else {
            return favouritesFirst(items, frecency: frecency)
        }
        let names = SearchSynonyms.expansions(for: query)
        return items.enumerated()
            .compactMap { offset, item -> (offset: Int, isTypo: Bool, total: Int, frecency: Double, item: T)? in
                let text = key(item)
                guard let match = bestMatch(of: query, names: names, in: text) else {
                    return nil
                }
                let favourite = frecency(item)
                let total = match.isTypo ? match.score : match.score + SearchFrecency.bonus(forScore: favourite)
                return (offset, match.isTypo, total, favourite, item)
            }
            .sorted { lhs, rhs in
                if lhs.isTypo != rhs.isTypo {
                    return !lhs.isTypo
                }
                if lhs.total != rhs.total {
                    return lhs.total > rhs.total
                }
                if lhs.frecency != rhs.frecency {
                    return lhs.frecency > rhs.frecency
                }
                return lhs.offset < rhs.offset
            }
            .map(\.item)
    }

    /// The items with the ones opened from the search first, the most favoured at the front.
    /// Items with equal frecency keep their order, so with nothing stored nothing moves.
    static func favouritesFirst<T>(_ items: [T], frecency: (T) -> Double) -> [T] {
        items.enumerated()
            .map { (offset: $0.offset, frecency: frecency($0.element), item: $0.element) }
            .sorted { lhs, rhs in
                lhs.frecency != rhs.frecency ? lhs.frecency > rhs.frecency : lhs.offset < rhs.offset
            }
            .map(\.item)
    }

    /// The better of the typed text and the full names of a short name, in one candidate.
    private static func bestMatch(of query: String, names: [String], in text: String) -> FuzzyMatch.Match? {
        var best = FuzzyMatch.match(query: query, in: text)
        for name in names {
            guard let found = FuzzyMatch.match(query: name, in: text), !found.isTypo else {
                continue
            }
            let candidate = FuzzyMatch.Match(isTypo: false, score: found.score - synonymPenalty)
            if best.map(candidate.isBetter(than:)) ?? true {
                best = candidate
            }
        }
        return best
    }
}
