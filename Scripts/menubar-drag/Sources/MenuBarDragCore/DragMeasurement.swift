//
//  DragMeasurement.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// How the menu bar is built on the macOS the probe runs on.
///
/// Before macOS 27 every item is its own window and holzBar's dividers decide the sections by
/// position. On macOS 27 MenuBarAgent draws the whole bar, holzBar's dividers are never drawn and
/// the sections are kept per application.
public enum Generation: String, Sendable, Equatable {
    case before27
    case macOS27
}

/// A section of the menu bar as holzBar's dividers draw it.
public enum BarSection: String, Sendable, Equatable {
    case visible
    case hidden
    case alwaysHidden
}

/// One item of the menu bar as Accessibility reports it.
public struct BarItem: Sendable, Equatable {
    /// What an item is, as far as the probe tells.
    public enum Kind: String, Sendable, Equatable {
        case app
        case system
        case holzBarIcon
        case hiddenDivider
        case alwaysHiddenDivider
        case holzBarOther
    }

    /// `<owner>#<n>`, with `n` the index of the item in its owner's extras bar.
    public let id: String

    /// The bundle identifier of the owning application.
    public let owner: String

    public let kind: Kind

    /// The frame in CoreGraphics global coordinates (origin top left).
    public let frame: CGRect

    public init(id: String, owner: String, kind: Kind, frame: CGRect) {
        self.id = id
        self.owner = owner
        self.kind = kind
        self.frame = frame
    }

    /// Whether the item takes room in the bar. holzBar's collapsed items and folded items are
    /// 4 points wide or narrower.
    public var counts: Bool {
        frame.width > 4
    }
}

/// The menu bar of one display at one moment.
public struct BarSnapshot: Sendable, Equatable {
    public let generation: Generation
    public let displayID: UInt32
    public let displayBounds: CGRect

    /// The bottom edge of the bar in CoreGraphics coordinates.
    public let barMaxY: CGFloat

    /// Every item read, sorted by the left edge.
    public let items: [BarItem]

    public init(
        generation: Generation,
        displayID: UInt32,
        displayBounds: CGRect,
        barMaxY: CGFloat,
        items: [BarItem]
    ) {
        self.generation = generation
        self.displayID = displayID
        self.displayBounds = displayBounds
        self.barMaxY = barMaxY
        self.items = items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The counted item under a point, only inside the bar strip of this display.
    public func item(at point: CGPoint) -> BarItem? {
        guard displayBounds.contains(point), point.y <= barMaxY else {
            return nil
        }
        return items.first { $0.counts && $0.frame.minX <= point.x && point.x <= $0.frame.maxX }
    }

    public func item(withID id: String) -> BarItem? {
        items.first { $0.id == id }
    }

    /// The ids of the counted items, left to right.
    public func orderedIDs() -> [String] {
        items.filter(\.counts).map(\.id)
    }

    /// The position of an item in `orderedIDs()`.
    public func index(of id: String) -> Int? {
        orderedIDs().firstIndex(of: id)
    }

    /// The section an item sits in according to holzBar's dividers.
    ///
    /// On macOS 27 sections come from holzBar's saved layout per application, not from
    /// positions, so the answer is `nil` there, for items that are not applications' and when no
    /// hidden divider takes room in the bar.
    public func positionalSection(of item: BarItem) -> BarSection? {
        guard generation == .before27, item.kind == .app || item.kind == .holzBarOther else {
            return nil
        }
        guard let hiddenDivider = items.first(where: { $0.kind == .hiddenDivider && $0.counts }) else {
            return nil
        }
        if item.frame.midX > hiddenDivider.frame.maxX {
            return .visible
        }
        if let alwaysHiddenDivider = items.first(where: { $0.kind == .alwaysHiddenDivider && $0.counts }),
           item.frame.midX < alwaysHiddenDivider.frame.minX {
            return .alwaysHidden
        }
        return .hidden
    }
}

/// How one drag changed the bar, as the bounded reads after the drop show it.
public struct SettleResult: Sendable, Equatable {
    /// What a drag changed.
    public enum Scope: String, Sendable, Equatable {
        case reorder
        case section
        case none
    }

    public let moved: Bool
    public let scope: Scope

    /// The offset from the release to the last change, `nil` when nothing changed.
    public let settleMs: Int?

    /// The changes after the first one, a proxy for flicker.
    public let bounces: Int

    /// Whether the dragged item was missing in any read.
    public let vanished: Bool

    /// Whether the item was still where the settled read put it five seconds after the drop,
    /// `nil` without that read.
    public let persisted: Bool?

    public let fromIndex: Int?
    public let toIndex: Int?
    public let fromSection: BarSection?
    public let toSection: BarSection?

    public init(
        moved: Bool,
        scope: Scope,
        settleMs: Int?,
        bounces: Int,
        vanished: Bool,
        persisted: Bool?,
        fromIndex: Int?,
        toIndex: Int?,
        fromSection: BarSection?,
        toSection: BarSection?
    ) {
        self.moved = moved
        self.scope = scope
        self.settleMs = settleMs
        self.bounces = bounces
        self.vanished = vanished
        self.persisted = persisted
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.fromSection = fromSection
        self.toSection = toSection
    }
}

/// The bounded reads after one drop. Nothing is read between drops.
public enum SettleSeries {
    /// One read of the bar, taken `offsetMs` after the release.
    public struct Sample: Sendable, Equatable {
        public let offsetMs: Int
        public let snapshot: BarSnapshot

        public init(offsetMs: Int, snapshot: BarSnapshot) {
            self.offsetMs = offsetMs
            self.snapshot = snapshot
        }
    }

    /// When the bar is read after a drop, in milliseconds after the release. The last read only
    /// tells whether the result persisted.
    public static let offsetsMs = [50, 100, 200, 350, 500, 750, 1000, 1500, 2000, 5000]

    /// The reads up to this offset count for settling.
    private static let settlingLimitMs = 2000

    /// The offset of the read that only tells whether the result persisted.
    private static let persistenceOffsetMs = 5000

    /// The items and whole-point left edges of the counted items, which is what "changed" means.
    private struct Signature: Equatable {
        let entries: [Entry]

        struct Entry: Equatable {
            let id: String
            let minX: Int
        }

        init(_ snapshot: BarSnapshot) {
            entries = snapshot.items.filter(\.counts).map { Entry(id: $0.id, minX: Int($0.frame.minX.rounded())) }
        }
    }

    /// Evaluates the reads taken after a drop of `draggedID`.
    public static func evaluate(before: BarSnapshot, draggedID: String, samples: [Sample]) -> SettleResult {
        let ordered = samples.sorted { $0.offsetMs < $1.offsetMs }
        let counting = ordered.filter { $0.offsetMs <= settlingLimitMs }

        var previous = Signature(before)
        var changedOffsets = [Int]()
        for sample in counting {
            let signature = Signature(sample.snapshot)
            if signature != previous {
                changedOffsets.append(sample.offsetMs)
            }
            previous = signature
        }

        let vanished = ordered.contains { $0.snapshot.index(of: draggedID) == nil }
        let final = counting.last?.snapshot ?? before

        let fromIndex = before.index(of: draggedID)
        let toIndex = final.index(of: draggedID)
        let fromSection = before.item(withID: draggedID).flatMap { before.positionalSection(of: $0) }
        let toSection = final.item(withID: draggedID).flatMap { final.positionalSection(of: $0) }

        var moved = false
        if fromIndex != nil, toIndex != nil {
            moved = fromIndex != toIndex || fromSection != toSection
        }

        var persisted: Bool?
        if let settled = ordered.first(where: { $0.offsetMs == persistenceOffsetMs })?.snapshot {
            let settledSection = settled.item(withID: draggedID).flatMap { settled.positionalSection(of: $0) }
            persisted = settled.index(of: draggedID) == toIndex && settledSection == toSection
        }

        let scope: SettleResult.Scope
        if let fromSection, let toSection, fromSection != toSection {
            scope = .section
        } else {
            scope = moved ? .reorder : .none
        }

        return SettleResult(
            moved: moved,
            scope: scope,
            settleMs: changedOffsets.last,
            bounces: max(0, changedOffsets.count - 1),
            vanished: vanished,
            persisted: persisted,
            fromIndex: fromIndex,
            toIndex: toIndex,
            fromSection: fromSection,
            toSection: toSection
        )
    }
}

/// One line of the probe's report: a tag followed by `key=value` pairs in the order added.
public struct ReportLine: Sendable, Equatable {
    private let tag: String
    private var pairs = [(key: String, value: String)]()

    public init(_ tag: String) {
        self.tag = tag
    }

    public static func == (lhs: ReportLine, rhs: ReportLine) -> Bool {
        lhs.text == rhs.text
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

    public mutating func add(_ key: String, _ value: CGFloat?) {
        add(key, value.map { String(format: "%.1f", Double($0)) } ?? "-")
    }

    /// The tag followed by ` key=value` for every pair.
    public var text: String {
        pairs.reduce(tag) { $0 + " \($1.key)=\($1.value)" }
    }
}
