import Testing

@testable import HolzBarCore

@Suite("LayoutDraft")
struct LayoutDraftTests {
    private typealias Draft = LayoutDraft
    private typealias Entry = LayoutDraft.Entry

    private func entries(_ keys: String...) -> [Entry] {
        keys.map { Entry(key: $0) }
    }

    /// visible: a b c · hidden: d e · always hidden: f
    private func draft(ordersWithinSection: Bool = true, newItems: Draft.Section = .hidden) -> Draft {
        Draft(
            sections: [
                .visible: entries("a", "b", "c"),
                .hidden: entries("d", "e"),
                .alwaysHidden: entries("f"),
            ],
            newItems: newItems,
            ordersWithinSection: ordersWithinSection
        )
    }

    private func keys(_ draft: Draft, _ section: Draft.Section) -> [String] {
        draft.entries(in: section).map(\.key)
    }

    @Test("A new draft equals the bar and holds no change")
    func unchanged() {
        let draft = draft()
        #expect(!draft.isChanged)
        #expect(draft.changeCount == 0)
        #expect(draft.changedKeys.isEmpty)
        #expect(!draft.hasOrderChanges)
        #expect(keys(draft, .visible) == ["a", "b", "c"])
        #expect(draft.section(of: "e") == .hidden)
        #expect(draft.section(of: "zzz") == nil)
    }

    @Test("Moving an item to another section changes the drawing and nothing else")
    func moveToSection() {
        var draft = draft()
        draft.move("b", to: .hidden, before: "e")
        #expect(keys(draft, .visible) == ["a", "c"])
        #expect(keys(draft, .hidden) == ["d", "b", "e"])
        #expect(draft.changedKeys == ["b": .hidden])
        #expect(draft.isChanged)
        #expect(draft.changeCount == 1)
        #expect(draft.baselineSection(of: "b") == .visible)
    }

    @Test("A place that does not exist means the end of the section")
    func missingPlace() {
        var draft = draft()
        draft.move("a", to: .alwaysHidden, before: "nobody")
        #expect(keys(draft, .alwaysHidden) == ["f", "a"])
        draft.move("b", to: .alwaysHidden)
        #expect(keys(draft, .alwaysHidden) == ["f", "a", "b"])
        draft.moveToEnd("f", of: .alwaysHidden)
        #expect(keys(draft, .alwaysHidden) == ["a", "b", "f"])
    }

    @Test("Moving within a section reorders the drawing and counts as one change")
    func reorder() {
        var draft = draft()
        draft.move("c", to: .visible, before: "a")
        #expect(keys(draft, .visible) == ["c", "a", "b"])
        #expect(draft.changedKeys.isEmpty)
        #expect(draft.hasOrderChanges)
        #expect(draft.isChanged)
        #expect(draft.changeCount == 1)
    }

    @Test("Placing an item right of another puts it in that item's section")
    func rightOf() {
        var draft = draft()
        draft.move("a", rightOf: "d")
        #expect(keys(draft, .hidden) == ["d", "a", "e"])
        draft.move("f", rightOf: "e")
        #expect(keys(draft, .hidden) == ["d", "a", "e", "f"])
        draft.move("e", rightOf: "e")
        #expect(keys(draft, .hidden) == ["d", "a", "e", "f"])
        draft.move("c", rightOf: "b")
        #expect(keys(draft, .visible) == ["b", "c"])
    }

    @Test("Moving an item back leaves nothing to apply")
    func movedBack() {
        var draft = draft()
        draft.move("b", to: .hidden)
        draft.move("b", to: .visible, before: "c")
        #expect(keys(draft, .visible) == ["a", "b", "c"])
        #expect(!draft.isChanged)
    }

    @Test("Discarding makes the drawing equal to the bar again")
    func discard() {
        var draft = draft()
        draft.move("a", to: .hidden)
        draft.setNewItems(.visible)
        #expect(draft.isChanged)
        draft.discard()
        #expect(!draft.isChanged)
        #expect(keys(draft, .visible) == ["a", "b", "c"])
        #expect(draft.newItems == .hidden)
    }

    @Test("The new-items tile is one change when it moved")
    func newItemsTile() {
        var draft = draft(newItems: .hidden)
        #expect(draft.newItems == .hidden)
        draft.setNewItems(.alwaysHidden)
        #expect(draft.isChanged)
        #expect(draft.changeCount == 1)
        draft.setNewItems(.hidden)
        #expect(!draft.isChanged)
    }

    @Test("A locked item cannot be moved and is never a change")
    func locked() {
        var draft = Draft(
            sections: [.visible: [Entry(key: "icon", isLocked: true), Entry(key: "a")]],
            newItems: .visible,
            ordersWithinSection: true
        )
        draft.move("icon", to: .hidden)
        #expect(keys(draft, .visible) == ["icon", "a"])
        #expect(!draft.isChanged)
    }

    @Test("Items of one group move together, the one that was dragged first")
    func groups() {
        var draft = Draft(
            sections: [
                .visible: [Entry(key: "mail 1", group: "mail"), Entry(key: "x"), Entry(key: "mail 2", group: "mail")],
                .hidden: [Entry(key: "y")],
            ],
            newItems: .visible,
            ordersWithinSection: false
        )
        draft.move("mail 2", to: .hidden)
        #expect(keys(draft, .visible) == ["x"])
        #expect(keys(draft, .hidden) == ["y", "mail 2", "mail 1"])
        #expect(draft.changedKeys == ["mail 1": .hidden, "mail 2": .hidden])
        #expect(draft.changedGroups == ["mail": .hidden])
    }

    @Test("A move within a section moves only the item, a move into another section moves its group")
    func sameSectionMovesTheItemAlone() {
        func grouped() -> Draft {
            Draft(
                sections: [
                    .visible: [Entry(key: "a", group: "G"), Entry(key: "x"), Entry(key: "a2", group: "G"), Entry(key: "y")],
                    .hidden: [Entry(key: "h")],
                ],
                newItems: .visible,
                ordersWithinSection: true
            )
        }
        var draft = grouped()
        draft.move("a", to: .visible, before: "y")
        #expect(keys(draft, .visible) == ["x", "a2", "a", "y"])
        #expect(draft.changedKeys.isEmpty)
        #expect(draft.hasOrderChanges)
        var toHidden = grouped()
        toHidden.move("a", to: .hidden)
        #expect(keys(toHidden, .visible) == ["x", "y"])
        #expect(keys(toHidden, .hidden) == ["h", "a", "a2"])
        var rightOf = grouped()
        rightOf.move("a", rightOf: "x")
        #expect(keys(rightOf, .visible) == ["x", "a", "a2", "y"])
    }

    @Test("Moving an item before another and back leaves a drawing equal to the bar")
    func moveAndMoveBack() {
        var draft = Draft(
            sections: [.visible: [Entry(key: "a", group: "G"), Entry(key: "x"), Entry(key: "a2", group: "G"), Entry(key: "y")]],
            newItems: .visible,
            ordersWithinSection: true
        )
        draft.move("x", to: .visible, before: "a")
        #expect(keys(draft, .visible) == ["x", "a", "a2", "y"])
        #expect(draft.hasOrderChanges)
        draft.move("x", to: .visible, before: "a2")
        #expect(keys(draft, .visible) == ["a", "x", "a2", "y"])
        #expect(!draft.hasOrderChanges)
        #expect(!draft.isChanged)
    }

    @Test("An item moved into another section before a given item sits there in the drawing")
    func intoAnotherSectionByPosition() {
        var draft = draft()
        draft.move("b", to: .hidden, before: "e")
        #expect(keys(draft, .hidden) == ["d", "b", "e"])
        #expect(draft.changedKeys == ["b": .hidden])
    }

    @Test("A locked entry never moves")
    func lockedNeverMoves() {
        var draft = Draft(
            sections: [.visible: [Entry(key: "pinned", isLocked: true), Entry(key: "a"), Entry(key: "b")]],
            newItems: .visible,
            ordersWithinSection: true
        )
        draft.move("pinned", to: .visible, before: "b")
        #expect(keys(draft, .visible) == ["pinned", "a", "b"])
        #expect(!draft.isChanged)
    }

    @Test("Without an order within sections only the section counts")
    func sectionsOnly() {
        var draft = draft(ordersWithinSection: false)
        draft.move("c", to: .visible, before: "a")
        #expect(keys(draft, .visible) == ["a", "b", "c"])
        #expect(!draft.isChanged)
        draft.move("a", to: .hidden, before: "d")
        #expect(keys(draft, .hidden) == ["d", "e", "a"])
        #expect(draft.changeCount == 1)
        #expect(!draft.hasOrderChanges)
    }

    @Test("A section that is empty still exists in the drawing")
    func emptySections() {
        let draft = Draft(sections: [.visible: entries("a")], newItems: .visible, ordersWithinSection: true)
        #expect(draft.entries(in: .alwaysHidden).isEmpty)
        #expect(draft.orderTargets[.hidden] == [])
    }

    // MARK: Following the bar

    @Test("A bar that did not change leaves the drawing as drawn")
    func rebaseSame() {
        var draft = draft()
        draft.move("a", to: .hidden)
        let sections: [Draft.Section: [Entry]] = [
            .visible: entries("a", "b", "c"),
            .hidden: entries("d", "e"),
            .alwaysHidden: entries("f"),
        ]
        draft.rebase(onto: sections, newItems: .hidden)
        #expect(keys(draft, .hidden) == ["d", "e", "a"])
        #expect(draft.changedKeys == ["a": .hidden])
    }

    @Test("An item that left the bar leaves the drawing, one that came appears where the bar has it")
    func rebaseArrivalAndDeparture() {
        var draft = draft()
        draft.move("a", to: .hidden)
        let sections: [Draft.Section: [Entry]] = [
            .visible: entries("a", "b", "g"),
            .hidden: entries("d", "e"),
            .alwaysHidden: entries("f"),
        ]
        draft.rebase(onto: sections, newItems: .hidden)
        #expect(keys(draft, .visible) == ["b", "g"])
        #expect(keys(draft, .hidden) == ["d", "e", "a"])
        #expect(draft.section(of: "c") == nil)
        #expect(draft.changedKeys == ["a": .hidden])
    }

    @Test("An item the user did not touch follows the bar, one the user moved stays")
    func rebaseFollowsTheBar() {
        var draft = draft()
        draft.move("a", to: .alwaysHidden)
        // Elsewhere, b went to the hidden section.
        let sections: [Draft.Section: [Entry]] = [
            .visible: entries("a", "c"),
            .hidden: entries("d", "e", "b"),
            .alwaysHidden: entries("f"),
        ]
        draft.rebase(onto: sections, newItems: .hidden)
        #expect(draft.section(of: "b") == .hidden)
        #expect(draft.section(of: "a") == .alwaysHidden)
        #expect(draft.changedKeys == ["a": .alwaysHidden])
    }

    @Test("The order drawn in a section stands while the section is as it was")
    func rebaseKeepsOrder() {
        var draft = draft()
        draft.move("c", to: .visible, before: "a")
        let sections: [Draft.Section: [Entry]] = [
            .visible: entries("a", "b", "c"),
            .hidden: entries("d", "e", "g"),
            .alwaysHidden: entries("f"),
        ]
        draft.rebase(onto: sections, newItems: .hidden)
        #expect(keys(draft, .visible) == ["c", "a", "b"])
        #expect(keys(draft, .hidden) == ["d", "e", "g"])
        #expect(draft.hasOrderChanges)
    }

    @Test("The new-items tile follows the bar until the user moves it")
    func rebaseTile() {
        var draft = draft(newItems: .hidden)
        let same = draft.baseline
        draft.rebase(onto: same, newItems: .visible)
        #expect(draft.newItems == .visible)
        #expect(!draft.isChanged)
        draft.setNewItems(.alwaysHidden)
        draft.rebase(onto: same, newItems: .hidden)
        #expect(draft.newItems == .alwaysHidden)
        #expect(draft.isChanged)
    }

    @Test("A drawing equal to the bar after the bar changed holds no change")
    func rebaseBecomesEqual() {
        var draft = draft()
        draft.move("a", to: .hidden)
        // The user's move happened on the bar meanwhile.
        let sections: [Draft.Section: [Entry]] = [
            .visible: entries("b", "c"),
            .hidden: entries("d", "e", "a"),
            .alwaysHidden: entries("f"),
        ]
        draft.rebase(onto: sections, newItems: .hidden)
        #expect(!draft.isChanged)
    }
}

@Suite("ReorderPlan")
struct ReorderPlanTests {
    /// Makes the moves on a row the way the bar does.
    private func apply(_ moves: [ReorderPlan.Move], to row: [String]) -> [String] {
        var row = row
        for move in moves {
            row.removeAll { $0 == move.key }
            if let before = move.before, let index = row.firstIndex(of: before) {
                row.insert(move.key, at: index)
            } else {
                row.append(move.key)
            }
        }
        return row
    }

    private func permutations(of items: [String]) -> [[String]] {
        guard items.count > 1 else {
            return [items]
        }
        return items.indices.flatMap { index -> [[String]] in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(of: rest).map { [head] + $0 }
        }
    }

    @Test("A row already in order needs no move")
    func sorted() {
        #expect(ReorderPlan.moves(actual: ["a", "b", "c"], desired: ["a", "b", "c"]).isEmpty)
        #expect(ReorderPlan.moves(actual: [], desired: []).isEmpty)
    }

    @Test("One item out of place takes one move")
    func oneMove() {
        let toFront = ReorderPlan.moves(actual: ["a", "b", "c", "d"], desired: ["d", "a", "b", "c"])
        #expect(toFront == [ReorderPlan.Move(key: "d", before: "a")])
        let toEnd = ReorderPlan.moves(actual: ["a", "b", "c", "d"], desired: ["b", "c", "d", "a"])
        #expect(toEnd == [ReorderPlan.Move(key: "a", before: nil)])
    }

    @Test("Every order of five items is reached, in no more moves than items less one")
    func everyOrder() {
        let actual = ["a", "b", "c", "d", "e"]
        for desired in permutations(of: actual) {
            let moves = ReorderPlan.moves(actual: actual, desired: desired)
            #expect(apply(moves, to: actual) == desired)
            #expect(moves.count <= actual.count - 1)
            #expect(moves.isEmpty == (desired == actual))
        }
    }

    @Test("Every order of six items is reached from a shuffled row")
    func shuffledStart() {
        let actual = ["d", "a", "f", "b", "e", "c"]
        for desired in permutations(of: ["a", "b", "c", "d", "e", "f"]) {
            let moves = ReorderPlan.moves(actual: actual, desired: desired)
            #expect(apply(moves, to: actual) == desired)
        }
    }

    @Test("A key in only one row is ignored")
    func differentSets() {
        let moves = ReorderPlan.moves(actual: ["a", "x", "b", "c"], desired: ["c", "a", "y", "b"])
        #expect(apply(moves, to: ["a", "x", "b", "c"]).filter { $0 != "x" } == ["c", "a", "b"])
    }
}

@Suite("NewItemsLanding")
struct NewItemsLandingTests {
    @Test("A chosen section is where new items land")
    func chosen() {
        for isMacOS27 in [true, false] {
            #expect(NewItemsLanding.section(placement: 1, isMacOS27: isMacOS27, alwaysHiddenIsOn: false) == .visible)
            #expect(NewItemsLanding.section(placement: 2, isMacOS27: isMacOS27, alwaysHiddenIsOn: true) == .hidden)
            #expect(NewItemsLanding.section(placement: 3, isMacOS27: isMacOS27, alwaysHiddenIsOn: true) == .alwaysHidden)
            #expect(NewItemsLanding.section(placement: 3, isMacOS27: isMacOS27, alwaysHiddenIsOn: false) == .hidden)
        }
    }

    @Test("Where macOS puts them: visible on macOS 27, the leftmost section before")
    func systemDefault() {
        #expect(NewItemsLanding.section(placement: 0, isMacOS27: true, alwaysHiddenIsOn: true) == .visible)
        #expect(NewItemsLanding.section(placement: 0, isMacOS27: false, alwaysHiddenIsOn: true) == .alwaysHidden)
        #expect(NewItemsLanding.section(placement: 0, isMacOS27: false, alwaysHiddenIsOn: false) == .hidden)
        #expect(NewItemsLanding.section(placement: 99, isMacOS27: true, alwaysHiddenIsOn: false) == .visible)
    }

    @Test("A section maps back to the setting's number")
    func placement() {
        #expect(NewItemsLanding.placement(for: .visible) == 1)
        #expect(NewItemsLanding.placement(for: .hidden) == 2)
        #expect(NewItemsLanding.placement(for: .alwaysHidden) == 3)
    }
}
