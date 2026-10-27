//
//  ShelfLayout.swift
//  holzBar
//

import Foundation

/// How the holzBar Shelf arranges the items of a section.
nonisolated enum ShelfLayout: Int, CaseIterable, Identifiable, Sendable {
    /// One row, as wide as the items; it scrolls when the screen is too narrow.
    case row = 0
    /// Rows of a few items below each other.
    case grid = 1
    /// One item below the other.
    case column = 2

    var id: Int { rawValue }
}

nonisolated enum ShelfLayoutPlan {
    /// The items in a row of a grid.
    static let gridColumns = 6

    /// The most rows the Shelf shows before it scrolls.
    static let visibleRows = 10

    /// The items split into the rows the layout draws. Nothing is dropped or reordered, so
    /// reading the rows in order gives the items in order.
    static func rows<T>(of items: [T], layout: ShelfLayout, columns: Int = gridColumns) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }
        let width: Int
        switch layout {
        case .row: width = items.count
        case .grid: width = max(columns, 1)
        case .column: width = 1
        }
        return stride(from: 0, to: items.count, by: width).map { start in
            Array(items[start..<min(start + width, items.count)])
        }
    }

    /// The index the keyboard highlight moves to from `index`, or `nil` when it stays. Left and
    /// right step one item; up and down step a row, which means one item in a column and
    /// `columns` items in a grid, and do nothing in a single row.
    static func target(
        from index: Int,
        step: Step,
        count: Int,
        layout: ShelfLayout,
        columns: Int = gridColumns
    ) -> Int? {
        guard count > 0, (0..<count).contains(index) else {
            return nil
        }
        let distance: Int
        switch (step, layout) {
        case (.left, _): distance = -1
        case (.right, _): distance = 1
        case (.up, .grid): distance = -max(columns, 1)
        case (.down, .grid): distance = max(columns, 1)
        case (.up, .column): distance = -1
        case (.down, .column): distance = 1
        case (.up, .row), (.down, .row): return nil
        }
        let target = index + distance
        return (0..<count).contains(target) ? target : nil
    }

    nonisolated enum Step: Sendable {
        case left, right, up, down
    }
}
