//
//  ShelfLayoutTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("The holzBar Shelf's layouts")
struct ShelfLayoutTests {
    private let items = Array(1...14)

    @Test("A row keeps every item in one row")
    func row() {
        let rows = ShelfLayoutPlan.rows(of: items, layout: .row)
        let first = rows.first
        #expect(rows.count == 1)
        #expect(first == items)
    }

    @Test("A grid fills rows of six, the last one shorter")
    func grid() {
        let rows = ShelfLayoutPlan.rows(of: items, layout: .grid)
        let sizes = rows.map { $0.count }
        let flat = Array(rows.joined())
        #expect(sizes == [6, 6, 2])
        #expect(flat == items)
    }

    @Test("A column has one item in each row")
    func column() {
        let rows = ShelfLayoutPlan.rows(of: items, layout: .column)
        let flat = Array(rows.joined())
        #expect(rows.count == 14)
        #expect(flat == items)
    }

    @Test("No items make no rows, and a grid of no width still draws")
    func edges() {
        let none = ShelfLayoutPlan.rows(of: [Int](), layout: .grid)
        #expect(none.isEmpty)
        let oneWide = ShelfLayoutPlan.rows(of: [1, 2, 3], layout: .grid, columns: 0)
        #expect(oneWide.count == 3)
    }

    private func target(_ index: Int, _ step: ShelfLayoutPlan.Step, _ count: Int, _ layout: ShelfLayout) -> Int? {
        ShelfLayoutPlan.target(from: index, step: step, count: count, layout: layout)
    }

    @Test("The highlight moves by item, and by row in a grid or a column")
    func highlight() {
        let right = target(3, .right, 14, .grid)
        let down = target(3, .down, 14, .grid)
        let up = target(9, .up, 14, .grid)
        let lastRow = target(12, .down, 14, .grid)
        let columnDown = target(2, .down, 14, .column)
        let columnTop = target(0, .up, 14, .column)
        let rowDown = target(2, .down, 14, .row)
        let rowEnd = target(13, .right, 14, .row)
        let empty = target(0, .left, 0, .row)
        #expect(right == 4)
        #expect(down == 9)
        #expect(up == 3)
        #expect(lastRow == nil)
        #expect(columnDown == 3)
        #expect(columnTop == nil)
        #expect(rowDown == nil)
        #expect(rowEnd == nil)
        #expect(empty == nil)
    }
}

@Suite("The holzBar Shelf's fade")
struct ShelfAnimationTests {
    @Test("It lasts a moment, and not at all when off or with Reduce Motion")
    func duration() {
        let normal = ShelfAnimation.fadeDuration(isEnabled: true, reduceMotion: false)
        let off = ShelfAnimation.fadeDuration(isEnabled: false, reduceMotion: false)
        let reduced = ShelfAnimation.fadeDuration(isEnabled: true, reduceMotion: true)
        let isShort = normal > 0 && normal <= 0.2
        let isNone = off == 0 && reduced == 0
        #expect(isShort)
        #expect(isNone)
    }
}
