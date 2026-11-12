//
//  UndoHistory.swift
//  holzBar
//

import Foundation

/// The changes that can still be undone, newest last, kept in memory only.
///
/// It holds at most `capacity` entries; pushing beyond that drops the oldest, which the caller
/// gets back so it can let go of what they keep (for example a deleted group's settings).
nonisolated struct UndoHistory<Entry: Identifiable> {
    /// How many changes the history keeps when nothing else is asked for.
    static var defaultCapacity: Int { 20 }

    /// The most entries the history holds.
    let capacity: Int

    /// The entries, oldest first.
    private(set) var entries = [Entry]()

    init(capacity: Int = defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// The entry pushed last.
    var newest: Entry? {
        entries.last
    }

    /// Whether nothing can be undone.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Adds an entry as the newest.
    ///
    /// - Returns: The entries dropped beyond the capacity, oldest first.
    @discardableResult
    mutating func push(_ entry: Entry) -> [Entry] {
        entries.append(entry)
        let overflow = entries.count - capacity
        guard overflow > 0 else {
            return []
        }
        let dropped = Array(entries.prefix(overflow))
        entries.removeFirst(overflow)
        return dropped
    }

    /// Removes and returns the newest entry.
    mutating func popNewest() -> Entry? {
        entries.popLast()
    }

    /// Removes and returns the entry with the given identifier, or `nil` if there is none.
    mutating func remove(id: Entry.ID) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return entries.remove(at: index)
    }

    /// Removes every entry and returns them, oldest first.
    mutating func removeAll() -> [Entry] {
        let all = entries
        entries.removeAll()
        return all
    }
}

/// Puts a deleted element of a list back where it was.
nonisolated enum DeletionUndo {
    /// Inserts the element at its former index, clamped to the list as it is now.
    static func reinsert<Element>(_ element: Element, at index: Int, into list: inout [Element]) {
        list.insert(element, at: min(max(index, 0), list.count))
    }
}

/// Tells whether an undo of a layout change put everything back.
nonisolated enum ArrangementUndo {
    /// Whether the arrangement `now` places every item and application of `wanted` in the same
    /// section. Items and applications that are no longer there count as put back: they cannot
    /// be moved.
    static func isRestored(wanted: LayoutSnapshot, now: LayoutSnapshot) -> Bool {
        SnapshotDiff(from: now, to: wanted).moves == 0
    }

    /// Whether every item of the application is in the wanted section (macOS 27, where macOS
    /// places whole applications). An application without items counts as put back.
    static func isRestored(app: String, wantedSection: Int, sections: [(app: String?, section: Int)]) -> Bool {
        sections.allSatisfy { $0.app != app || $0.section == wantedSection }
    }
}
