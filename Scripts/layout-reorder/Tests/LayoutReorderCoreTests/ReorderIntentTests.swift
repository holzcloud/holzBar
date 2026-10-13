//
//  ReorderIntentTests.swift
//  holzBar
//

import Testing

@testable import LayoutReorderCore

private func ids(_ bar: FakeBar, _ section: SpikeSection) -> [String] {
    (bar.rows[section] ?? []).map(\.id)
}

private func request(
    _ sources: [String],
    to target: SpikeSection,
    _ position: ReorderRequest.Position = .end
) -> ReorderRequest {
    ReorderRequest(sources: sources, target: target, position: position)
}

@Suite("ReorderIntent")
struct ReorderIntentTests {
    let bar = FakeBar.make(itemCount: 12)

    @Test("The bar of 12 items has the planned rows, unique ids and is deterministic")
    func makeTwelve() {
        #expect(ids(bar, .visible) == [
            "holzbar.icon", "system.clock", "twoitems.0", "twoitems.1", "app.1", "app.2", "app.3",
        ])
        #expect(ids(bar, .hidden) == ["unknown.0", "busy.0", "widget.battery", "group.work"])
        #expect(ids(bar, .alwaysHidden) == ["spacer.0"])
        #expect(Set(bar.allItems.map(\.id)).count == 12)
        #expect(bar == FakeBar.make(itemCount: 12))
    }

    @Test("The item count is clamped to 10...80 and spreads over the rows")
    func makeClamped() {
        #expect(FakeBar.make(itemCount: 5).itemCount == 10)
        #expect(FakeBar.make(itemCount: 500).itemCount == 80)
        let forty = FakeBar.make(itemCount: 40)
        #expect(forty.itemCount == 40)
        #expect(forty.rows[.visible]?.count == 20)
        #expect(forty.rows[.hidden]?.count == 13)
        #expect(forty.rows[.alwaysHidden]?.count == 7)
    }

    @Test("Moving one item of an app moves every item of that app, in bar order")
    func wholeAppMoves() {
        let outcome = ReorderIntent.outcome(for: request(["twoitems.0"], to: .hidden), in: bar)
        #expect(outcome.moves.count == 1)
        #expect(outcome.moves.first?.itemIDs == ["twoitems.0", "twoitems.1"])
        #expect(outcome.intents == ["LayoutBarMoves.setSection(com.example.twoitems,.hidden)"])
        let after = bar.applying(outcome)
        #expect(ids(after, .hidden).suffix(2) == ["twoitems.0", "twoitems.1"])
        #expect(!ids(after, .visible).contains("twoitems.0"))
    }

    @Test("Two sources of one app in one request give one move")
    func oneMovePerKey() {
        let outcome = ReorderIntent.outcome(for: request(["twoitems.0", "twoitems.1"], to: .alwaysHidden), in: bar)
        #expect(outcome.moves.count == 1)
        #expect(outcome.refusals.isEmpty)
    }

    @Test("Every refusal the Layout pane makes is reproduced with its reason")
    func refusals() {
        let cases: [(String, SpikeSection, Refusal)] = [
            ("holzbar.icon", .hidden, .controlItem),
            ("system.clock", .hidden, .notMovable),
            ("unknown.0", .visible, .noApp),
            ("busy.0", .visible, .unresponsive),
            ("no.such.item", .visible, .unknownItem),
            ("app.2", .visible, .sameSection),
            ("holzbar.icon", .visible, .controlItem),
        ]
        for (id, target, reason) in cases {
            let outcome = ReorderIntent.outcome(for: request([id], to: target), in: bar)
            #expect(outcome.moves.isEmpty, "\(id) must not move")
            #expect(outcome.refusals == [.init(itemID: id, reason: reason)], "\(id) must be refused as \(reason)")
            #expect(outcome.intents.isEmpty)
        }
    }

    @Test("A mixed request gives its moves and refusals in source order")
    func mixedRequest() {
        let outcome = ReorderIntent.outcome(for: request(["app.1", "system.clock"], to: .hidden), in: bar)
        #expect(outcome.moves.map(\.key) == ["com.example.app1"])
        #expect(outcome.refusals == [.init(itemID: "system.clock", reason: .notMovable)])
    }

    @Test("A position before an item of the target row puts the item right before it")
    func positionBefore() {
        let outcome = ReorderIntent.outcome(for: request(["app.1"], to: .hidden, .before("busy.0")), in: bar)
        #expect(ids(bar.applying(outcome), .hidden) == ["unknown.0", "app.1", "busy.0", "widget.battery", "group.work"])
    }

    @Test("A position before an item that moves itself puts the items at the end")
    func positionBeforeMovedItem() {
        let outcome = ReorderIntent.outcome(for: request(["app.1"], to: .hidden, .before("app.1")), in: bar)
        #expect(ids(bar.applying(outcome), .hidden).last == "app.1")
    }

    @Test("An outcome with only refusals leaves the bar equal")
    func refusalsChangeNothing() {
        let outcome = ReorderIntent.outcome(for: request(["system.clock", "app.2"], to: .visible), in: bar)
        #expect(outcome.moves.isEmpty)
        #expect(bar.applying(outcome) == bar)
    }

    @Test("The request writes its position as end or before:<id>")
    func positionText() {
        #expect(request(["a"], to: .hidden).positionText == "end")
        #expect(request(["a"], to: .hidden, .before("b")).positionText == "before:b")
    }

    @Test("The refusal texts are the Layout pane's")
    func messages() {
        #expect(Refusal.sameSection.message(itemName: "X") == "macOS orders the items within each section.")
        #expect(Refusal.unresponsive.message(itemName: "Busy App").hasPrefix("Busy App is unresponsive."))
    }

    @Test("The focus target stops at the ends of a row")
    func focusWithinRow() {
        #expect(bar.focusTarget(fromRow: 0, index: 0, dx: -1, dy: 0) == (0, 0))
        #expect(bar.focusTarget(fromRow: 0, index: 6, dx: 1, dy: 0) == (0, 6))
        #expect(bar.focusTarget(fromRow: 0, index: 2, dx: 1, dy: 0) == (0, 3))
    }

    @Test("The focus target skips empty rows, keeps the nearest index and stays at the last row")
    func focusBetweenRows() {
        #expect(bar.focusTarget(fromRow: 0, index: 6, dx: 0, dy: 1) == (1, 3))
        #expect(bar.focusTarget(fromRow: 1, index: 2, dx: 0, dy: 1) == (2, 0))
        #expect(bar.focusTarget(fromRow: 2, index: 0, dx: 0, dy: 1) == (2, 0))
        #expect(bar.focusTarget(fromRow: 0, index: 1, dx: 0, dy: -1) == (0, 1))
        var emptied = bar
        emptied.rows[.hidden] = []
        #expect(emptied.focusTarget(fromRow: 0, index: 4, dx: 0, dy: 1) == (2, 0))
        #expect(emptied.focusTarget(fromRow: 2, index: 0, dx: 0, dy: -1) == (0, 0))
    }
}
