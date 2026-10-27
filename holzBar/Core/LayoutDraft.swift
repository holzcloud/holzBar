//
//  LayoutDraft.swift
//  holzBar
//

import Foundation

/// The draft of the Menu Bar Layout pane: a drawing of the sections that the bar follows once
/// the user applies it.
///
/// A draft starts as a copy of the bar (its baseline). Dragging an item in the pane changes only
/// the drawing (``current``); the bar stays as it is until the user applies the draft, which
/// moves what differs in one pass (``changedKeys``, ``orderTargets``), or discards it. Nothing
/// here touches the bar, the screen or the defaults: the pane reads the bar into entries and
/// moves the items the draft names.
///
/// An item is an ``Entry`` with a stable key (its identity in the saved layout) and a group. On
/// macOS 27 the section belongs to an application, so every item of one application has the
/// same group and moves with it; macOS also orders the items within a section, so a draft built
/// with `ordersWithinSection` off records sections only. Before macOS 27 each item is its own
/// group and the order within a section is part of the drawing.
nonisolated struct LayoutDraft: Equatable, Sendable {
    /// The sections of the bar, in the order the pane lists them.
    nonisolated enum Section: Int, CaseIterable, Hashable, Sendable {
        case visible = 0
        case hidden = 1
        case alwaysHidden = 2
    }

    /// An item in the drawing.
    nonisolated struct Entry: Hashable, Sendable {
        /// Identifies the item across reads of the bar.
        var key: String
        /// Items of one group change section together: the items of an application on macOS 27.
        var group: String
        /// Whether the item cannot be moved (holzBar's own control items, an item macOS pins).
        var isLocked: Bool

        init(key: String, group: String? = nil, isLocked: Bool = false) {
            self.key = key
            self.group = group ?? key
            self.isLocked = isLocked
        }
    }

    /// The bar as it was read.
    private(set) var baseline: [Section: [Entry]]

    /// The drawing.
    private(set) var current: [Section: [Entry]]

    /// The section new items land in on the bar, as it is now.
    private(set) var baselineNewItems: Section

    /// The section new items land in, in the drawing.
    private(set) var newItems: Section

    /// Whether the order within a section is part of the drawing.
    let ordersWithinSection: Bool

    /// Creates a draft that equals the bar.
    init(sections: [Section: [Entry]], newItems: Section, ordersWithinSection: Bool) {
        var complete = [Section: [Entry]]()
        for section in Section.allCases {
            complete[section] = sections[section] ?? []
        }
        self.baseline = complete
        self.current = complete
        self.baselineNewItems = newItems
        self.newItems = newItems
        self.ordersWithinSection = ordersWithinSection
    }

    // MARK: Reading

    /// The entries of a section in the drawing, from left to right.
    func entries(in section: Section) -> [Entry] {
        current[section] ?? []
    }

    /// The section an item is in, in the drawing.
    func section(of key: String) -> Section? {
        Section.allCases.first { section in entries(in: section).contains { $0.key == key } }
    }

    /// The entry of an item in the drawing.
    private func entry(for key: String) -> Entry? {
        for section in Section.allCases {
            if let found = entries(in: section).first(where: { $0.key == key }) {
                return found
            }
        }
        return nil
    }

    /// The section an item is in on the bar.
    func baselineSection(of key: String) -> Section? {
        Section.allCases.first { section in (baseline[section] ?? []).contains { $0.key == key } }
    }

    // MARK: Changing

    /// Moves an item in the drawing, together with the items of its group.
    ///
    /// - Parameters:
    ///   - key: The item.
    ///   - section: The section to move it to.
    ///   - other: The item to put it before, or `nil` for the end of the section. An item that
    ///     is not in the section, or that moves with this one, counts as `nil`. Without
    ///     `ordersWithinSection` the place is always the end, and a move within a section
    ///     changes nothing.
    mutating func move(_ key: String, to section: Section, before other: String? = nil) {
        guard
            let entry = entry(for: key),
            !entry.isLocked,
            let source = self.section(of: key)
        else {
            return
        }
        if !ordersWithinSection, source == section {
            return
        }
        // The item first, then the others of its group, wherever they were.
        var moved = [entry]
        for candidate in Section.allCases {
            for mate in entries(in: candidate) where mate.group == entry.group && mate.key != key && !mate.isLocked {
                moved.append(mate)
            }
        }
        let movedKeys = Set(moved.map(\.key))
        var updated = current
        for candidate in Section.allCases {
            updated[candidate] = entries(in: candidate).filter { !movedKeys.contains($0.key) }
        }
        var destination = updated[section] ?? []
        var index = destination.count
        if ordersWithinSection, let other, !movedKeys.contains(other), let found = destination.firstIndex(where: { $0.key == other }) {
            index = found
        }
        destination.insert(contentsOf: moved, at: index)
        updated[section] = destination
        current = updated
    }

    /// Moves an item to the end of a section.
    mutating func moveToEnd(_ key: String, of section: Section) {
        move(key, to: section, before: nil)
    }

    /// Moves an item to be right of another item, in the other item's section.
    mutating func move(_ key: String, rightOf other: String) {
        guard let section = section(of: other), key != other else {
            return
        }
        let entries = entries(in: section)
        guard let index = entries.firstIndex(where: { $0.key == other }) else {
            return
        }
        let group = entries.first { $0.key == key }?.group
        let next = entries[(index + 1)...].first { $0.key != key && $0.group != group }
        move(key, to: section, before: next?.key)
    }

    /// Sets the section new items land in.
    mutating func setNewItems(_ section: Section) {
        newItems = section
    }

    /// Makes the drawing equal to the bar again.
    mutating func discard() {
        current = baseline
        newItems = baselineNewItems
    }

    // MARK: Changes

    /// The sections of the items that are in another section than on the bar, by key.
    var changedKeys: [String: Section] {
        var result = [String: Section]()
        for section in Section.allCases {
            for entry in entries(in: section) where !entry.isLocked && baselineSection(of: entry.key) != section {
                result[entry.key] = section
            }
        }
        return result
    }

    /// The same by group: the section each group of items moves to.
    var changedGroups: [String: Section] {
        var result = [String: Section]()
        for section in Section.allCases {
            for entry in entries(in: section) where !entry.isLocked && baselineSection(of: entry.key) != section {
                result[entry.group] = section
            }
        }
        return result
    }

    /// Whether any item is in another place within the section it was in and stays in.
    var hasOrderChanges: Bool {
        ordersWithinSection && Section.allCases.contains { !orderMoves(in: $0).isEmpty }
    }

    /// The moves that bring a section's items into the drawing's order, once its items are in
    /// the right sections: only those that were in the section on the bar and still are.
    func orderMoves(in section: Section) -> [ReorderPlan.Move] {
        guard ordersWithinSection else {
            return []
        }
        let kept = Set(entries(in: section).map(\.key)).intersection((baseline[section] ?? []).map(\.key))
        return ReorderPlan.moves(
            actual: (baseline[section] ?? []).map(\.key).filter(kept.contains),
            desired: entries(in: section).map(\.key).filter(kept.contains)
        )
    }

    /// The order the drawing wants in each section, by key. For the pass that sorts the items
    /// once they are in their sections.
    var orderTargets: [Section: [String]] {
        var result = [Section: [String]]()
        for section in Section.allCases {
            result[section] = entries(in: section).map(\.key)
        }
        return result
    }

    /// Whether the drawing differs from the bar.
    var isChanged: Bool {
        newItems != baselineNewItems || !changedKeys.isEmpty || hasOrderChanges
    }

    /// How many changes the drawing holds: items in another section, items in another place and
    /// the new-items tile when it moved. Zero means the drawing equals the bar.
    var changeCount: Int {
        let sectionMoves = changedKeys.count
        let orderCount = ordersWithinSection ? Section.allCases.reduce(0) { $0 + orderMoves(in: $1).count } : 0
        return sectionMoves + orderCount + (newItems == baselineNewItems ? 0 : 1)
    }

    // MARK: Following the bar

    /// Reads the bar again and keeps what the user drew.
    ///
    /// The bar changes while the pane is open (an app opens and adds an item, another quits).
    /// An item that left is dropped from the drawing, an item that came appears in its section
    /// on the bar, and an item the user moved stays where the user put it. An item the user did
    /// not touch follows the bar. The order the user drew within a section is kept only while
    /// the section holds the same items in the same order as on the bar before.
    mutating func rebase(onto sections: [Section: [Entry]], newItems landing: Section) {
        var fresh = [Section: [Entry]]()
        for section in Section.allCases {
            fresh[section] = sections[section] ?? []
        }
        // The tile follows the bar unless the user moved it.
        if newItems == baselineNewItems {
            newItems = landing
        }
        baselineNewItems = landing
        guard fresh != baseline else {
            return
        }
        let freshByKey = fresh.values.joined().reduce(into: [String: Entry]()) { $0[$1.key] = $1 }
        var oldSections = [String: Section]()
        for section in Section.allCases {
            for entry in baseline[section] ?? [] {
                oldSections[entry.key] = section
            }
        }
        // The bar as it is now, with the order the user drew in the sections that did not change.
        var result = fresh
        for section in Section.allCases where ordersWithinSection {
            let before = (baseline[section] ?? []).map(\.key)
            let after = (fresh[section] ?? []).map(\.key)
            guard before == after else {
                continue
            }
            // Items the user moved away are still listed here; the moves below take them out.
            var reordered = entries(in: section).filter { oldSections[$0.key] == section }.compactMap { freshByKey[$0.key] }
            let listed = Set(reordered.map(\.key))
            reordered += (fresh[section] ?? []).filter { !listed.contains($0.key) }
            result[section] = reordered
        }
        // Then the moves of the user over it.
        for section in Section.allCases {
            let drawn = entries(in: section)
            for entry in drawn where !entry.isLocked && freshByKey[entry.key] != nil && oldSections[entry.key] != section {
                for candidate in Section.allCases {
                    result[candidate] = result[candidate]?.filter { $0.key != entry.key }
                }
                var target = result[section] ?? []
                var index = target.count
                if let drawnIndex = drawn.firstIndex(where: { $0.key == entry.key }) {
                    // After the entry that precedes it in the drawing, when that one is there.
                    let preceding = drawn[..<drawnIndex].reversed().first { predecessor in
                        target.contains { $0.key == predecessor.key }
                    }
                    if let preceding, let found = target.firstIndex(where: { $0.key == preceding.key }) {
                        index = found + 1
                    } else if ordersWithinSection {
                        index = 0
                    }
                }
                target.insert(freshByKey[entry.key] ?? entry, at: index)
                result[section] = target
            }
        }
        baseline = fresh
        current = result
    }
}

/// The smallest list of moves that puts a row of items into another order.
nonisolated enum ReorderPlan {
    /// Puts an item before another one, or at the end of the row.
    nonisolated struct Move: Equatable, Sendable {
        var key: String
        /// The item to put it before; `nil` for the end of the row.
        var before: String?
    }

    /// The moves, in the order to make them, that turn `actual` into `desired`. Both rows hold
    /// the same keys; a key in only one of them is ignored. Items that already keep their
    /// relative order (the longest run of them) stay where they are, so a row with one item out
    /// of place takes one move.
    static func moves(actual: [String], desired: [String]) -> [Move] {
        let inActual = Set(actual)
        let inDesired = Set(desired)
        let order = desired.filter(inActual.contains)
        let present = actual.filter(inDesired.contains)
        guard order != present, !order.isEmpty else {
            return []
        }
        let position = Dictionary(present.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let positions = order.compactMap { position[$0] }
        let stable = longestIncreasingRun(positions)
        var result = [Move]()
        for index in order.indices.reversed() where !stable.contains(index) {
            result.append(Move(key: order[index], before: index + 1 < order.count ? order[index + 1] : nil))
        }
        return result
    }

    /// The indices of a longest strictly increasing subsequence of the values.
    private static func longestIncreasingRun(_ values: [Int]) -> Set<Int> {
        guard !values.isEmpty else {
            return []
        }
        var length = [Int](repeating: 1, count: values.count)
        var previous = [Int?](repeating: nil, count: values.count)
        var best = 0
        for index in values.indices {
            for earlier in 0..<index where values[earlier] < values[index] && length[earlier] + 1 > length[index] {
                length[index] = length[earlier] + 1
                previous[index] = earlier
            }
            if length[index] > length[best] {
                best = index
            }
        }
        var result = Set<Int>()
        var cursor: Int? = best
        while let current = cursor {
            result.insert(current)
            cursor = previous[current]
        }
        return result
    }
}

/// Where items holzBar has never seen land, as the "New items" tile of the drawing shows it.
nonisolated enum NewItemsLanding {
    /// The section new items land in for the setting "Place new menu bar items in".
    ///
    /// - Parameters:
    ///   - placement: The raw value of the setting: 0 leaves them where macOS puts them, 1 is
    ///     visible, 2 hidden and 3 always hidden. Any other number counts as 0.
    ///   - isMacOS27: macOS 27 keeps a layout per application, and an application missing from
    ///     it is visible.
    ///   - alwaysHiddenIsOn: Whether the always-hidden section exists.
    /// - Returns: Before macOS 27, macOS adds a new item at the left edge, so it lands in the
    ///   leftmost section the bar has.
    static func section(placement: Int, isMacOS27: Bool, alwaysHiddenIsOn: Bool) -> LayoutDraft.Section {
        switch placement {
        case 1: return .visible
        case 2: return .hidden
        case 3: return alwaysHiddenIsOn ? .alwaysHidden : .hidden
        default:
            if isMacOS27 {
                return .visible
            }
            return alwaysHiddenIsOn ? .alwaysHidden : .hidden
        }
    }

    /// The raw value of the setting that places new items in a section.
    static func placement(for section: LayoutDraft.Section) -> Int {
        switch section {
        case .visible: 1
        case .hidden: 2
        case .alwaysHidden: 3
        }
    }
}
