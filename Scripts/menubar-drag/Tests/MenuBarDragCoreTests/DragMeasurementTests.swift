//
//  DragMeasurementTests.swift
//  holzBar
//

import CoreGraphics
import Testing

@testable import MenuBarDragCore

/// A before-27 bar on display 1, reused by the other test files of the target.
enum Fixture {
    static let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

    static func item(
        _ owner: String,
        _ index: Int,
        _ kind: BarItem.Kind,
        x: CGFloat,
        width: CGFloat = 30
    ) -> BarItem {
        BarItem(
            id: "\(owner)#\(index)",
            owner: owner,
            kind: kind,
            frame: CGRect(x: x, y: 0, width: width, height: 24)
        )
    }

    /// The bar with `b` and `c` in the given places and any extra items.
    static func bar(
        generation: Generation = .before27,
        bX: CGFloat = 420,
        cX: CGFloat = 460,
        hiddenDivider: Bool = true,
        extra: [BarItem] = []
    ) -> BarSnapshot {
        var items = [
            item("com.holzcloud.holzBar", 2, .alwaysHiddenDivider, x: 250, width: 18),
            item("com.example.a", 0, .app, x: 280),
            item("com.example.b", 0, .app, x: bX),
            item("com.example.c", 0, .app, x: cX),
            item("com.holzcloud.holzBar", 0, .holzBarIcon, x: 500, width: 26),
            item("com.apple.controlcenter", 0, .system, x: 1300, width: 80),
        ]
        if hiddenDivider {
            items.append(item("com.holzcloud.holzBar", 1, .hiddenDivider, x: 380, width: 18))
        }
        return BarSnapshot(
            generation: generation,
            displayID: 1,
            displayBounds: bounds,
            barMaxY: 24,
            items: items + extra
        )
    }

    static let before = bar()
    static let swapped = bar(bX: 460, cX: 420)
    static let bInHidden = bar(bX: 330)
    static let b = "com.example.b#0"

    static func samples(_ pairs: [(Int, BarSnapshot)]) -> [SettleSeries.Sample] {
        pairs.map { SettleSeries.Sample(offsetMs: $0.0, snapshot: $0.1) }
    }

    /// Reads at every offset up to 2000 ms, the first `changeAt` ones of them still showing `before`.
    static func series(changeAt: Int, to snapshot: BarSnapshot) -> [SettleSeries.Sample] {
        SettleSeries.offsetsMs.filter { $0 <= 2000 }.map {
            SettleSeries.Sample(offsetMs: $0, snapshot: $0 < changeAt ? before : snapshot)
        }
    }
}

@Suite("DragMeasurement")
struct DragMeasurementTests {
    @Test("item(at:) finds b at its centre, nothing below the bar and nothing on a 3-point item")
    func hitTest() {
        let bar = Fixture.bar(extra: [Fixture.item("com.example.thin", 0, .app, x: 700, width: 3)])
        #expect(bar.item(at: CGPoint(x: 435, y: 12))?.id == Fixture.b)
        #expect(bar.item(at: CGPoint(x: 435, y: 30)) == nil)
        #expect(bar.item(at: CGPoint(x: 701, y: 12)) == nil)
    }

    @Test("positional sections follow the dividers and are unknown without them or on macOS 27")
    func positionalSections() throws {
        let bar = Fixture.before
        let a = try #require(bar.item(withID: "com.example.a#0"))
        let b = try #require(bar.item(withID: Fixture.b))
        #expect(bar.positionalSection(of: a) == .hidden)
        #expect(bar.positionalSection(of: b) == .visible)

        let added = Fixture.item("com.example.added", 0, .app, x: 200)
        let withAdded = Fixture.bar(extra: [added])
        #expect(withAdded.positionalSection(of: added) == .alwaysHidden)

        let withoutDivider = Fixture.bar(hiddenDivider: false)
        #expect(withoutDivider.positionalSection(of: try #require(withoutDivider.item(withID: Fixture.b))) == nil)

        let on27 = Fixture.bar(generation: .macOS27)
        #expect(on27.positionalSection(of: try #require(on27.item(withID: Fixture.b))) == nil)
    }

    @Test("orderedIDs() leaves out items of 4 points or less")
    func orderedIDs() {
        let bar = Fixture.bar(extra: [
            Fixture.item("com.example.thin", 0, .app, x: 700, width: 4),
            Fixture.item("com.example.thinner", 0, .app, x: 720, width: 0),
        ])
        #expect(!bar.orderedIDs().contains("com.example.thin#0"))
        #expect(!bar.orderedIDs().contains("com.example.thinner#0"))
        #expect(bar.orderedIDs().contains(Fixture.b))
        #expect(bar.orderedIDs().first == "com.holzcloud.holzBar#2")
    }

    @Test("b moving right of c at 100 ms and staying is one reorder that settled at 100 ms")
    func plainReorder() {
        let result = SettleSeries.evaluate(
            before: Fixture.before,
            draggedID: Fixture.b,
            samples: Fixture.series(changeAt: 100, to: Fixture.swapped)
        )
        #expect(result.moved)
        #expect(result.scope == .reorder)
        #expect(result.settleMs == 100)
        #expect(result.bounces == 0)
        #expect(result.persisted == nil)
        #expect(result.fromIndex == 3)
        #expect(result.toIndex == 4)
    }

    @Test("a change at 50 ms, back at 100 ms and the move at 350 ms count as two bounces")
    func bouncing() {
        let samples = Fixture.samples([
            (50, Fixture.swapped),
            (100, Fixture.before),
            (200, Fixture.before),
            (350, Fixture.swapped),
            (500, Fixture.swapped),
            (2000, Fixture.swapped),
        ])
        let result = SettleSeries.evaluate(before: Fixture.before, draggedID: Fixture.b, samples: samples)
        #expect(result.bounces == 2)
        #expect(result.settleMs == 350)
        #expect(result.moved)
    }

    @Test("b ending left of the hidden divider is a move between sections")
    func sectionMove() {
        let result = SettleSeries.evaluate(
            before: Fixture.before,
            draggedID: Fixture.b,
            samples: Fixture.series(changeAt: 200, to: Fixture.bInHidden)
        )
        #expect(result.scope == .section)
        #expect(result.fromSection == .visible)
        #expect(result.toSection == .hidden)
        #expect(result.moved)
    }

    @Test("a bar that never changes is not moved and has no settle time")
    func nothingChanges() {
        let result = SettleSeries.evaluate(
            before: Fixture.before,
            draggedID: Fixture.b,
            samples: Fixture.series(changeAt: 10_000, to: Fixture.before)
        )
        #expect(!result.moved)
        #expect(result.scope == .none)
        #expect(result.settleMs == nil)
        #expect(result.bounces == 0)
    }

    @Test("the dragged item missing from one read is vanished")
    func vanishing() {
        let without = BarSnapshot(
            generation: .before27,
            displayID: 1,
            displayBounds: Fixture.bounds,
            barMaxY: 24,
            items: Fixture.before.items.filter { $0.id != Fixture.b }
        )
        let samples = Fixture.samples([
            (100, Fixture.before),
            (200, without),
            (350, Fixture.before),
        ])
        let result = SettleSeries.evaluate(before: Fixture.before, draggedID: Fixture.b, samples: samples)
        #expect(result.vanished)
    }

    @Test("the read five seconds after the drop tells whether the result persisted")
    func persistence() {
        let settled = Fixture.series(changeAt: 100, to: Fixture.swapped)
        let kept = SettleSeries.evaluate(
            before: Fixture.before,
            draggedID: Fixture.b,
            samples: settled + [SettleSeries.Sample(offsetMs: 5000, snapshot: Fixture.swapped)]
        )
        #expect(kept.persisted == true)
        let reverted = SettleSeries.evaluate(
            before: Fixture.before,
            draggedID: Fixture.b,
            samples: settled + [SettleSeries.Sample(offsetMs: 5000, snapshot: Fixture.before)]
        )
        #expect(reverted.persisted == false)
    }

    @Test("ReportLine keeps the order of keys, quotes a value with a space and writes nil as a dash")
    func reportLine() {
        var line = ReportLine("TEST")
        line.add("zeta", "one")
        line.add("alpha", "two words")
        line.add("count", 3 as Int?)
        line.add("missing", nil as Int?)
        line.add("flag", true as Bool?)
        line.add("gone", nil as Bool?)
        line.add("shift", 2.54 as CGFloat?)
        line.add("quote", "say \"hi\"")
        #expect(line.text == "TEST zeta=one alpha=\"two words\" count=3 missing=- flag=yes gone=- shift=2.5 quote=\"say 'hi'\"")
    }
}
