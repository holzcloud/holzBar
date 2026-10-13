//
//  ReorderIntent.swift
//  holzBar
//

import Foundation

/// What a drop asks for: the items dragged, the row they were dropped in and where in it.
public struct ReorderRequest: Equatable, Sendable {
    public enum Position: Equatable, Sendable {
        case before(String)
        case end
    }

    public let sources: [String]
    public let target: SpikeSection
    public let position: Position

    public init(sources: [String], target: SpikeSection, position: Position) {
        self.sources = sources
        self.target = target
        self.position = position
    }

    /// `end` or `before:<id>`.
    public var positionText: String {
        switch position {
        case .end: "end"
        case .before(let id): "before:\(id)"
        }
    }
}

/// Why the Layout pane does not move an item.
public enum Refusal: String, Sendable {
    case unknownItem, controlItem, notMovable, noApp, unresponsive, sameSection

    /// The text the Layout pane shows or says for the refusal.
    public func message(itemName: String) -> String {
        switch self {
        case .unknownItem:
            "The item is gone."
        case .controlItem:
            "holzBar's own items keep their section."
        case .notMovable:
            "macOS 27 doesn't let apps hide this system item."
        case .noApp:
            "macOS 27 hides whole apps, and holzBar can't tell which app this item belongs to."
        case .unresponsive:
            "\(itemName) is unresponsive. Until it is restarted, it cannot be moved. "
                + "Movement of other menu bar items may also be affected until this is resolved."
        case .sameSection:
            "macOS orders the items within each section."
        }
    }
}

/// What a request does: the moves made and the items refused.
public struct ReorderOutcome: Equatable, Sendable {
    /// One app's items going to another row.
    public struct Move: Equatable, Sendable {
        public let key: String
        public let itemIDs: [String]
        public let from: SpikeSection
        public let to: SpikeSection
        public let position: ReorderRequest.Position

        public init(
            key: String,
            itemIDs: [String],
            from: SpikeSection,
            to: SpikeSection,
            position: ReorderRequest.Position
        ) {
            self.key = key
            self.itemIDs = itemIDs
            self.from = from
            self.to = to
            self.position = position
        }
    }

    /// One item that is not moved.
    public struct Refused: Equatable, Sendable {
        public let itemID: String
        public let reason: Refusal

        public init(itemID: String, reason: Refusal) {
            self.itemID = itemID
            self.reason = reason
        }
    }

    public var moves: [Move]
    public var refusals: [Refused]

    public init(moves: [Move] = [], refusals: [Refused] = []) {
        self.moves = moves
        self.refusals = refusals
    }

    /// The calls holzBar makes, `LayoutBarMoves.setSection(<key>,.<row>)` per move.
    public var intents: [String] {
        moves.map { "LayoutBarMoves.setSection(\($0.key),.\($0.to.rawValue))" }
    }
}

/// The macOS 27 rules of holzBar's Layout pane: whole apps change sections and macOS orders the
/// items inside one. Before macOS 27 this API does not exist, so the older ordering rules are
/// not mirrored.
public enum ReorderIntent {
    /// What dropping the request's items on the bar does.
    ///
    /// For each source, in order, the first matching rule decides: the bar does not have it,
    /// `unknownItem`; a control item, `controlItem`; not movable, `notMovable`; no app, `noApp`;
    /// unresponsive app, `unresponsive`; already in the target row, `sameSection`. Every other
    /// source is accepted, and the accepted ones make one move per app: all items of the bar with
    /// that key change the row.
    public static func outcome(for request: ReorderRequest, in bar: FakeBar) -> ReorderOutcome {
        var outcome = ReorderOutcome()
        var keys = [String]()
        var origins = [String: SpikeSection]()
        for id in request.sources {
            guard let item = bar.item(withID: id), let row = bar.section(of: id) else {
                outcome.refusals.append(.init(itemID: id, reason: .unknownItem))
                continue
            }
            if let reason = refusal(of: item, in: row, target: request.target) {
                outcome.refusals.append(.init(itemID: id, reason: reason))
                continue
            }
            if let key = item.key, origins[key] == nil {
                keys.append(key)
                origins[key] = row
            }
        }
        for key in keys {
            guard let origin = origins[key] else {
                continue
            }
            outcome.moves.append(.init(
                key: key,
                itemIDs: bar.allItems.filter { $0.key == key }.map(\.id),
                from: origin,
                to: request.target,
                position: request.position
            ))
        }
        return outcome
    }

    private static func refusal(of item: FakeItem, in row: SpikeSection, target: SpikeSection) -> Refusal? {
        if item.kind == .controlItem {
            return .controlItem
        }
        if !item.isMovable {
            return .notMovable
        }
        if item.key == nil {
            return .noApp
        }
        if item.isUnresponsive {
            return .unresponsive
        }
        if row == target {
            return .sameSection
        }
        return nil
    }
}
