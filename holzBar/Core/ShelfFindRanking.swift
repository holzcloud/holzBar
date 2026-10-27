//
//  ShelfFindRanking.swift
//  holzBar
//

import Foundation

nonisolated extension ShelfFind {
    /// The identifiers of the tiles whose name matches the query, best first, with holzBar's
    /// fuzzy search (`FuzzyMatch`). Nothing matches while nothing is typed.
    func matches(in tiles: [ShelfTile]) -> [String] {
        guard isActive else {
            return []
        }
        return FuzzyMatch.rank(tiles.filter(\.isSearchable), query: query) { $0.name }.map(\.id)
    }
}
