//
//  MoveNeighbourCheck.swift
//  holzBar
//

import Foundation

/// The check of which other items a move pushed out of their places before macOS 27.
///
/// A move is one synthetic drag of one item. It must leave the relative order of every other
/// item, the dividers included, unchanged. When macOS or the drag shifted a neighbour across a
/// divider or another item (a neighbour pushed into Hidden or Always Hidden), the order of the
/// others differs before and after, and this check names the items that left their place.
///
/// The item that moved never counts: it is meant to change its place. The check is pure; reading
/// the window list, logging and the repair are the app's.
nonisolated enum MoveNeighbourCheck {
    /// One item or divider on the bar: its window and its left edge.
    struct Entry: Equatable, Sendable {
        /// The window of the item.
        let id: UInt32
        /// The left edge of the window on the screen.
        let minX: Double
    }

    /// The ids of the items other than `moved` whose place in the order changed between the two
    /// reads, sorted ascending. An id that is only in one of the reads is ignored. Items with the
    /// same left edge are ordered by id, so the result is the same on every run.
    ///
    /// The items that kept their relative order are the longest increasing subsequence of the
    /// ranks (``ItemOrder/stableIndices(of:)``); the others are the ones that were pushed.
    static func disturbed(before: [Entry], after: [Entry], moved: UInt32) -> [UInt32] {
        let afterIDs = Set(after.map(\.id))
        let beforeOrder = ordered(before.filter { $0.id != moved && afterIDs.contains($0.id) })
        let beforeIDs = Set(beforeOrder)
        let afterOrder = ordered(after.filter { $0.id != moved && beforeIDs.contains($0.id) })

        var rankByID = [UInt32: Int]()
        for (rank, id) in beforeOrder.enumerated() {
            rankByID[id] = rank
        }
        let ranks = afterOrder.compactMap { rankByID[$0] }
        let stable = ItemOrder.stableIndices(of: ranks)
        let result = afterOrder.indices.filter { !stable.contains($0) }.map { afterOrder[$0] }
        return result.sorted()
    }

    /// The ids by left edge, then by id; a repeated id counts once (its first place).
    private static func ordered(_ entries: [Entry]) -> [UInt32] {
        var seen = Set<UInt32>()
        return entries
            .sorted { ($0.minX, $0.id) < ($1.minX, $1.id) }
            .compactMap { seen.insert($0.id).inserted ? $0.id : nil }
    }
}
