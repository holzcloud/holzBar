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
///
/// When the characters are not all there in order, a misspelt query can still match: if
/// it is a few edits (a character added, missing, replaced, or two neighbours swapped)
/// away from a word of the candidate, or from the start of one, it matches with fewer
/// edits ranking higher. Queries of 4 to 7 characters may be 1 edit off, longer ones 2;
/// shorter queries must match in order. Such typo matches always rank below every match
/// in order.
nonisolated enum FuzzyMatch {
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
    nonisolated private struct Position {
        let character: Character
        let startsWord: Bool
        let isCamelCaseHump: Bool
    }

    /// The score of `query` in `candidate`.
    ///
    /// - Returns: `nil` when the query's characters do not all appear in the candidate in
    ///   order; otherwise the score of the best match, higher is better.
    static func score(query: String, in candidate: String) -> Int? {
        score(of: queryCharacters(query), in: positions(of: candidate))
    }

    /// The fewest edits that turn `query` into a word of `candidate`, or the start of one.
    ///
    /// An edit adds, removes or replaces a character, or swaps two neighbouring ones. Case,
    /// diacritics, the query's spaces and the candidate's punctuation are ignored, and the
    /// words that follow a word count as its continuation, so a query can span words.
    ///
    /// - Returns: `nil` when the query is shorter than 4 characters or more edits away than
    ///   its length allows (1 edit for 4 to 7 characters, 2 for 8 or more).
    static func typoEdits(query: String, in candidate: String) -> Int? {
        typoEdits(of: queryCharacters(query), in: positions(of: candidate))
    }

    /// The edits a query of the given length may be off by; 0 when it must match in order.
    static func allowedEdits(forQueryLength length: Int) -> Int {
        switch length {
        case ..<4: 0
        case 4...7: 1
        default: 2
        }
    }

    /// The in-order score of the folded query `characters` in the candidate's `positions`.
    private static func score(of characters: [Character], in positions: [Position]) -> Int? {
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
        let characters = queryCharacters(query)
        return items.enumerated()
            .compactMap { offset, item -> (offset: Int, isTypo: Bool, score: Int, item: T)? in
                let positions = Self.positions(of: key(item))
                if let inOrder = Self.score(of: characters, in: positions) {
                    return (offset, false, inOrder, item)
                }
                if let edits = Self.typoEdits(of: characters, in: positions) {
                    return (offset, true, -edits, item)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.isTypo != rhs.isTypo {
                    return !lhs.isTypo
                }
                return lhs.score != rhs.score ? lhs.score > rhs.score : lhs.offset < rhs.offset
            }
            .map(\.item)
    }

    // MARK: Private

    /// `string` without case and diacritics.
    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The folded characters of `query`, without its spaces.
    private static func queryCharacters(_ query: String) -> [Character] {
        Array(fold(query).filter { !$0.isWhitespace })
    }

    /// The fewest edits between the folded query `characters` and a prefix of the
    /// candidate's letters and digits that starts at a word, or `nil` beyond the bound.
    ///
    /// This is the optimal string alignment form of the Damerau–Levenshtein distance,
    /// computed one candidate character at a time in two rows that are reused for every
    /// word. The last entry of a row is the distance to the prefix read so far; once every
    /// entry of a row exceeds the bound, longer prefixes cannot come closer, so the word is
    /// left early.
    private static func typoEdits(of characters: [Character], in positions: [Position]) -> Int? {
        let maxEdits = allowedEdits(forQueryLength: characters.count)
        guard maxEdits > 0 else {
            return nil
        }
        let count = characters.count
        // previousRow: the row of the prefix one character shorter. currentRow holds the
        // row of the prefix two characters shorter until it is overwritten.
        var previousRow = [Int](repeating: 0, count: count + 1)
        var currentRow = [Int](repeating: 0, count: count + 1)
        var fewest = Int.max

        for (start, position) in positions.enumerated() where position.startsWord && isWordCharacter(position.character) {
            for index in 0...count {
                previousRow[index] = index
            }
            var previousCharacter: Character?
            var length = 0
            for candidatePosition in positions[start...] where isWordCharacter(candidatePosition.character) {
                let character = candidatePosition.character
                length += 1
                // The entries of the row two characters shorter at index - 1 and index - 2,
                // read before they are overwritten, for a swap of neighbours.
                var twoShorterBeforeOne = 0
                var twoShorterBeforeTwo = 0
                var rowMinimum = Int.max
                for index in 0...count {
                    let twoShorter = currentRow[index]
                    var edits = length
                    if index > 0 {
                        let substitution = previousRow[index - 1] + (characters[index - 1] == character ? 0 : 1)
                        edits = min(previousRow[index] + 1, currentRow[index - 1] + 1, substitution)
                        if
                            index > 1,
                            let previousCharacter,
                            characters[index - 1] == previousCharacter,
                            characters[index - 2] == character
                        {
                            edits = min(edits, twoShorterBeforeTwo + 1)
                        }
                    }
                    currentRow[index] = edits
                    rowMinimum = min(rowMinimum, edits)
                    twoShorterBeforeTwo = twoShorterBeforeOne
                    twoShorterBeforeOne = twoShorter
                }
                fewest = min(fewest, currentRow[count])
                swap(&previousRow, &currentRow)
                previousCharacter = character
                if rowMinimum > maxEdits {
                    break
                }
            }
        }
        return fewest <= maxEdits ? fewest : nil
    }

    /// A Boolean value that indicates whether the folded `character` belongs to a word.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
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
