//
//  FuzzyMatch.swift
//  holzBar
//

import Foundation

/// holzBar's fuzzy search, used by the menu bar item search.
///
/// A query matches a candidate when its characters appear in the candidate in the same
/// order, ignoring case, diacritics and the query's spaces. Among all the ways the
/// characters can be found, the best one is scored: matches at the start, at the start of
/// a word and at camel-case humps score higher, so do consecutive characters, and gaps
/// cost a little. Typing "cc" therefore ranks "Control Centre" above "accent".
enum FuzzyMatch {
    /// The score of every matched character.
    private static let matchScore = 16
    /// The extra score of a match at the very start of the candidate.
    private static let startBonus = 24
    /// The extra score of a match at the start of a word.
    private static let boundaryBonus = 16
    /// The extra score of a match at a camel-case hump ("C" in "iCloud").
    private static let camelCaseBonus = 16
    /// The extra score of a match right after the previous one.
    private static let consecutiveBonus = 12
    /// The cost of every candidate character skipped between two matches.
    private static let gapPenalty = 3
    /// The cost of every candidate character before the first match.
    private static let leadingPenalty = 1
    /// The cost of every candidate character after the last match.
    private static let trailingPenalty = 1
    /// The extra score of a candidate that is the query itself.
    private static let exactBonus = 32

    /// A character of a candidate, folded for comparison, with what it starts.
    private struct Position {
        let character: Character
        let startsWord: Bool
        let isCamelCaseHump: Bool
    }

    /// The score of `query` in `candidate`.
    ///
    /// - Returns: `nil` when the query's characters do not all appear in the candidate in
    ///   order; otherwise the score of the best match, higher is better.
    static func score(query: String, in candidate: String) -> Int? {
        let characters = Array(fold(query).filter { !$0.isWhitespace })
        let positions = Self.positions(of: candidate)
        guard !characters.isEmpty, characters.count <= positions.count else {
            return nil
        }

        // best[j]: the best score with the current query character matched at position j.
        let impossible = Int.min / 4
        var best = [Int](repeating: impossible, count: positions.count)
        for (j, position) in positions.enumerated() where position.character == characters[0] {
            best[j] = characterScore(position, at: j) - leadingPenalty * j
        }

        for queryIndex in 1..<characters.count {
            var next = [Int](repeating: impossible, count: positions.count)
            // The best of best[k] + gapPenalty * k over k <= j - 2, so a gap costs
            // gapPenalty for every skipped character without a nested loop.
            var bestBeforeGap = impossible
            for j in queryIndex..<positions.count {
                if j >= 2, best[j - 2] > impossible {
                    bestBeforeGap = max(bestBeforeGap, best[j - 2] + gapPenalty * (j - 2))
                }
                guard positions[j].character == characters[queryIndex] else {
                    continue
                }
                var previous = impossible
                if best[j - 1] > impossible {
                    previous = best[j - 1] + consecutiveBonus
                }
                if bestBeforeGap > impossible {
                    previous = max(previous, bestBeforeGap - gapPenalty * (j - 1))
                }
                if previous > impossible {
                    next[j] = previous + characterScore(positions[j], at: j)
                }
            }
            best = next
        }

        var result = impossible
        for (j, score) in best.enumerated() where score > impossible {
            result = max(result, score - trailingPenalty * (positions.count - 1 - j))
        }
        guard result > impossible else {
            return nil
        }
        if characters == positions.map(\.character).filter({ !$0.isWhitespace }) {
            result += exactBonus
        }
        return result
    }

    /// The items whose key matches `query`, best first.
    ///
    /// Items with equal scores keep their order. An empty query returns all the items in
    /// their order.
    ///
    /// - Parameters:
    ///   - items: The items to search.
    ///   - query: What the user typed.
    ///   - key: The text of an item that is searched.
    static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        guard query.contains(where: { !$0.isWhitespace }) else {
            return items
        }
        return items.enumerated()
            .compactMap { offset, item -> (offset: Int, score: Int, item: T)? in
                guard let score = Self.score(query: query, in: key(item)) else {
                    return nil
                }
                return (offset, score, item)
            }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.offset < rhs.offset
            }
            .map(\.item)
    }

    // MARK: Private

    /// `string` without case and diacritics.
    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The folded characters of `candidate`, each with the word and hump it starts.
    ///
    /// A character that folds to several ("ß" to "ss") gives a position for each; only the
    /// first of them can start a word or a hump.
    private static func positions(of candidate: String) -> [Position] {
        var positions = [Position]()
        var previous: Character?
        for character in candidate {
            let startsWord = previous.map { !($0.isLetter || $0.isNumber) } ?? true
            let isCamelCaseHump = character.isUppercase && (previous?.isLowercase ?? false)
            for (offset, folded) in fold(String(character)).enumerated() {
                positions.append(
                    Position(
                        character: folded,
                        startsWord: offset == 0 && startsWord,
                        isCamelCaseHump: offset == 0 && isCamelCaseHump
                    )
                )
            }
            previous = character
        }
        return positions
    }

    /// The score of a match at `position`, the `index`-th position of the candidate.
    private static func characterScore(_ position: Position, at index: Int) -> Int {
        var score = matchScore
        if index == 0 {
            score += startBonus
        }
        if position.startsWord {
            score += boundaryBonus
        }
        if position.isCamelCaseHump {
            score += camelCaseBonus
        }
        return score
    }
}
