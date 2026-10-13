//
//  SpikeData.swift
//  holzBar
//

import Foundation

/// A row of the Layout pane, top to bottom in the order of the cases.
public enum SpikeSection: String, CaseIterable, Hashable, Sendable {
    case visible
    case hidden
    case alwaysHidden

    /// The headline above the row.
    public var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

/// A fake menu bar item: a name, a width and a symbol, nothing of another app.
public struct FakeItem: Identifiable, Hashable, Sendable {
    /// What an item is, as far as the Layout pane's rules tell.
    public enum Kind: String, Hashable, Sendable {
        case app, system, controlItem, widget, group, spacer
    }

    public let id: String
    public let name: String

    /// What macOS 27 places: the app's bundle identifier or a widget's own key; `nil` when
    /// holzBar cannot tell the app.
    public let key: String?
    public let kind: Kind

    /// The width of the item's picture in points.
    public let width: Double

    /// An SF Symbol name; `nil` draws nothing (the spacer).
    public let symbol: String?

    /// `false` for a system item macOS 27 cannot hide.
    public let isMovable: Bool
    public let isUnresponsive: Bool

    public init(
        id: String,
        name: String,
        key: String?,
        kind: Kind,
        width: Double,
        symbol: String?,
        isMovable: Bool = true,
        isUnresponsive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.kind = kind
        self.width = width
        self.symbol = symbol
        self.isMovable = isMovable
        self.isUnresponsive = isUnresponsive
    }
}

/// The three rows of fake items.
public struct FakeBar: Equatable, Sendable {
    /// Every section is present, possibly empty.
    public var rows: [SpikeSection: [FakeItem]]

    public init(rows: [SpikeSection: [FakeItem]]) {
        var complete = rows
        for section in SpikeSection.allCases where complete[section] == nil {
            complete[section] = []
        }
        self.rows = complete
    }

    /// The number of items in all rows.
    public var itemCount: Int {
        rows.values.reduce(0) { $0 + $1.count }
    }

    /// The items, rows top to bottom and left to right.
    public var allItems: [FakeItem] {
        SpikeSection.allCases.flatMap { rows[$0] ?? [] }
    }

    public func item(withID id: String) -> FakeItem? {
        allItems.first { $0.id == id }
    }

    public func section(of id: String) -> SpikeSection? {
        SpikeSection.allCases.first { section in
            rows[section]?.contains { $0.id == id } == true
        }
    }

    /// The bar after an outcome: for each move in order, its items leave every row and enter
    /// the target row, before the item the move names when that item is in the row and does
    /// not move itself, otherwise at the end. Refusals change nothing.
    public func applying(_ outcome: ReorderOutcome) -> FakeBar {
        var bar = self
        for move in outcome.moves {
            let moving = move.itemIDs.compactMap { bar.item(withID: $0) }
            for section in SpikeSection.allCases {
                bar.rows[section]?.removeAll { move.itemIDs.contains($0.id) }
            }
            var row = bar.rows[move.to] ?? []
            var index = row.count
            if case .before(let id) = move.position, let found = row.firstIndex(where: { $0.id == id }) {
                index = found
            }
            row.insert(contentsOf: moving, at: index)
            bar.rows[move.to] = row
        }
        return bar
    }

    /// Where the focus goes for a focus command (`dx` along a row, `dy` between rows).
    ///
    /// A mirror of holzBar's `LayoutKeys.focusTarget`, which a replacement would use directly.
    /// Within a row the focus stops at either end. Between rows it skips empty rows and lands on
    /// the item nearest the same index; at the first or last row it stays.
    public func focusTarget(fromRow row: Int, index: Int, dx: Int, dy: Int) -> (row: Int, index: Int) {
        let counts = SpikeSection.allCases.map { rows[$0]?.count ?? 0 }
        guard counts.indices.contains(row) else {
            return (row, index)
        }
        if dy == 0 {
            let count = counts[row]
            guard count > 0 else {
                return (row, index)
            }
            return (row, min(max(index + dx, 0), count - 1))
        }
        let step = dy > 0 ? 1 : -1
        var next = row + step
        while counts.indices.contains(next) {
            if counts[next] > 0 {
                return (next, min(max(index, 0), counts[next] - 1))
            }
            next += step
        }
        return (row, index)
    }

    /// The fixed items, the first nine of every bar.
    private static let fixed: [SpikeSection: [FakeItem]] = [
        .visible: [
            FakeItem(
                id: "holzbar.icon",
                name: "holzBar",
                key: "com.holzcloud.holzBar",
                kind: .controlItem,
                width: 22,
                symbol: "line.3.horizontal"
            ),
            FakeItem(
                id: "system.clock",
                name: "Clock",
                key: "com.apple.menuextra.clock",
                kind: .system,
                width: 60,
                symbol: "clock",
                isMovable: false
            ),
            FakeItem(
                id: "twoitems.0",
                name: "Two Items (1)",
                key: "com.example.twoitems",
                kind: .app,
                width: 24,
                symbol: "music.note"
            ),
            FakeItem(
                id: "twoitems.1",
                name: "Two Items (2)",
                key: "com.example.twoitems",
                kind: .app,
                width: 24,
                symbol: "music.note.list"
            ),
        ],
        .hidden: [
            FakeItem(
                id: "unknown.0",
                name: "Unknown Item",
                key: nil,
                kind: .app,
                width: 24,
                symbol: "questionmark.square"
            ),
            FakeItem(
                id: "busy.0",
                name: "Busy App",
                key: "com.example.busy",
                kind: .app,
                width: 24,
                symbol: "hourglass",
                isUnresponsive: true
            ),
            FakeItem(
                id: "widget.battery",
                name: "Battery Widget",
                key: "widget:Battery",
                kind: .widget,
                width: 44,
                symbol: "battery.75percent"
            ),
            FakeItem(
                id: "group.work",
                name: "Work Group",
                key: "group:Work",
                kind: .group,
                width: 24,
                symbol: "square.grid.2x2"
            ),
        ],
        .alwaysHidden: [
            FakeItem(
                id: "spacer.0",
                name: "Spacer",
                key: "spacer:0",
                kind: .spacer,
                width: 12,
                symbol: nil
            ),
        ],
    ]

    private static let symbols = [
        "wifi", "bolt.fill", "cloud.fill", "envelope.fill", "calendar",
        "magnifyingglass", "bell.fill", "lock.fill", "star.fill", "paperplane.fill",
    ]

    /// A deterministic bar of `itemCount` items, clamped to 10...80: nine fixed items (one per
    /// rule of the Layout pane), then generic apps.
    ///
    /// The keys of the group, spacer and widget are the spike's own (they are there for the
    /// drag of narrow, empty and wide pictures); the app keys them by `MenuBarItem.layoutKey27`,
    /// which the spike does not claim to mirror for them.
    public static func make(itemCount: Int) -> FakeBar {
        let count = min(max(itemCount, 10), 80)
        var rows = fixed
        for number in 1...(count - 9) {
            let slot = (number - 1) % 10
            let section: SpikeSection = switch slot {
            case 0...4: .visible
            case 5...7: .hidden
            default: .alwaysHidden
            }
            rows[section, default: []].append(FakeItem(
                id: "app.\(number)",
                name: "App \(number)",
                key: "com.example.app\(number)",
                kind: .app,
                width: 18 + Double((number * 7) % 27),
                symbol: symbols[slot]
            ))
        }
        return FakeBar(rows: rows)
    }
}

/// One line of the spike's report: a tag followed by `key=value` pairs in the order added.
public struct ReportLine: Sendable {
    private let tag: String
    private var pairs = [(key: String, value: String)]()

    public init(_ tag: String) {
        self.tag = tag
    }

    /// Adds a value. An empty value is written as `-`, a value with a space or an equals sign is
    /// quoted, and a double quote inside a value becomes a single quote.
    public mutating func add(_ key: String, _ value: String) {
        var shown = value.replacingOccurrences(of: "\"", with: "'")
        if shown.isEmpty {
            shown = "-"
        } else if shown.contains(" ") || shown.contains("=") {
            shown = "\"" + shown + "\""
        }
        pairs.append((key: key, value: shown))
    }

    public mutating func add(_ key: String, _ value: Int?) {
        add(key, value.map { String($0) } ?? "-")
    }

    public mutating func add(_ key: String, _ value: Bool?) {
        add(key, value.map { $0 ? "yes" : "no" } ?? "-")
    }

    public mutating func add(_ key: String, _ value: Double?, decimals: Int) {
        add(key, value.map { String(format: "%.\(decimals)f", $0) } ?? "-")
    }

    /// The tag followed by ` key=value` for every pair.
    public var text: String {
        pairs.reduce(tag) { $0 + " \($1.key)=\($1.value)" }
    }
}
