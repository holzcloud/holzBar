//
//  ShelfDrop.swift
//  holzBar
//

import Foundation

/// Where a tile dragged in the holzBar Shelf lands, from the pointer and the tiles' frames.
///
/// Every number is in AppKit's screen coordinates (the origin is the bottom left of the global
/// screen space, y grows upward), as ``HolzBarShelfPlacement`` uses them. The function never
/// reads the screen, the pointer or a view; the caller does, at each step of the drag.
///
/// A tile dropped on another item goes next to it (before macOS 27) or into its section (any
/// macOS, when it is another section); on the fold tile it goes into the always-hidden section;
/// above the Shelf, on the menu bar, it is shown there.
nonisolated enum ShelfDrop {
    /// What a tile is, as far as a drop is concerned.
    nonisolated enum Role: Equatable, Sendable {
        /// An item on the bar: it can be dropped on and dragged.
        case item
        /// The fold tile: a drop on it goes into the always-hidden section.
        case fold
        /// A closed application or a divider: nothing can be dropped on it.
        case other
    }

    /// One tile with its frame on the screen.
    nonisolated struct Tile: Equatable, Sendable {
        let id: String
        let group: ShelfGroup
        let role: Role
        let frame: HolzBarShelfPlacement.Rect

        init(id: String, group: ShelfGroup, role: Role, frame: HolzBarShelfPlacement.Rect) {
            self.id = id
            self.group = group
            self.role = role
            self.frame = frame
        }
    }

    /// Which way the Shelf lays its tiles out.
    nonisolated enum Axis: Equatable, Sendable {
        /// A row or a grid: the earlier tile is on the left.
        case horizontal
        /// A column: the earlier tile is above.
        case vertical
    }

    /// Which side of a tile a drop lands on.
    nonisolated enum Side: Equatable, Sendable {
        /// Before the tile: on its left, or above it in a column.
        case before
        /// After the tile.
        case after
    }

    /// What a drop does.
    nonisolated enum Outcome: Equatable, Sendable {
        /// Nothing: the pointer is not over a place that takes the tile.
        case none
        /// Next to another item.
        case beside(tile: String, side: Side)
        /// Into the section of a group, such as the always-hidden section for the fold tile.
        case section(ShelfGroup)
        /// Onto the menu bar: the item is shown there.
        case menuBar
    }

    /// The outcome of releasing `dragged` with the pointer at `pointer`.
    ///
    /// - Parameters:
    ///   - pointer: The pointer on the screen.
    ///   - dragged: The tile that is dragged.
    ///   - tiles: Every tile of the Shelf with its frame.
    ///   - panel: The Shelf's panel.
    ///   - screen: The frame of the screen the Shelf is on.
    ///   - axis: How the Shelf lays its tiles out.
    ///   - ordersItems: Whether the items of a section can be put in an order, which macOS 27
    ///     does itself: where it is `false` a drop on an item means its section, and a drop
    ///     into the dragged item's own section changes nothing.
    static func outcome(
        pointer: HolzBarShelfPlacement.Point,
        dragged: Tile,
        tiles: [Tile],
        panel: HolzBarShelfPlacement.Rect,
        screen: HolzBarShelfPlacement.Rect,
        axis: Axis,
        ordersItems: Bool
    ) -> Outcome {
        guard
            dragged.role == .item,
            dragged.group != .visible,
            pointer.x.isFinite, pointer.y.isFinite,
            contains(screen, pointer)
        else {
            return .none
        }

        // Above the Shelf is the menu bar (or the gap between them, when the Shelf floats).
        if pointer.y > panel.maxY {
            return .menuBar
        }
        guard contains(panel, pointer) else {
            return .none
        }

        // Released where it was picked up: nothing to do.
        guard !contains(dragged.frame, pointer) else {
            return .none
        }
        guard let target = target(at: pointer, excluding: dragged, in: tiles, axis: axis) else {
            return .none
        }
        switch target.role {
        case .other:
            return .none
        case .fold:
            return dragged.group == .alwaysHidden ? .none : .section(.alwaysHidden)
        case .item:
            guard target.group != .visible else {
                return .none
            }
            if ordersItems {
                return .beside(tile: target.id, side: side(of: pointer, in: target.frame, axis: axis))
            }
            return target.group == dragged.group ? .none : .section(target.group)
        }
    }

    /// The tile under the pointer, else the nearest one in the row (or column) the pointer is in.
    private static func target(
        at pointer: HolzBarShelfPlacement.Point,
        excluding dragged: Tile,
        in tiles: [Tile],
        axis: Axis
    ) -> Tile? {
        let others = tiles.filter { $0.id != dragged.id && $0.frame.isFinite }
        if let under = others.first(where: { contains($0.frame, pointer) }) {
            return under
        }
        // Between two tiles, or beside the last one: the nearest tile of the same row, so a
        // drop in a gap still lands next to a neighbour. Closed applications and dividers do not
        // count: nothing can be dropped on them.
        let band = others.filter { tile in
            guard tile.role != .other else {
                return false
            }
            switch axis {
            case .horizontal: return (tile.frame.minY...tile.frame.maxY).contains(pointer.y)
            case .vertical: return (tile.frame.minX...tile.frame.maxX).contains(pointer.x)
            }
        }
        return band.min { distance(from: pointer, to: $0.frame, axis: axis) < distance(from: pointer, to: $1.frame, axis: axis) }
    }

    /// The distance along the axis from the pointer to the frame's nearer edge.
    private static func distance(from pointer: HolzBarShelfPlacement.Point, to frame: HolzBarShelfPlacement.Rect, axis: Axis) -> Double {
        switch axis {
        case .horizontal:
            return pointer.x < frame.minX ? frame.minX - pointer.x : max(pointer.x - frame.maxX, 0)
        case .vertical:
            return pointer.y < frame.minY ? frame.minY - pointer.y : max(pointer.y - frame.maxY, 0)
        }
    }

    /// The side of the frame the pointer is on: the half nearer the start is before.
    private static func side(of pointer: HolzBarShelfPlacement.Point, in frame: HolzBarShelfPlacement.Rect, axis: Axis) -> Side {
        switch axis {
        case .horizontal: pointer.x < frame.x + frame.width / 2 ? .before : .after
        case .vertical: pointer.y > frame.y + frame.height / 2 ? .before : .after
        }
    }

    private static func contains(_ rect: HolzBarShelfPlacement.Rect, _ point: HolzBarShelfPlacement.Point) -> Bool {
        rect.isFinite && point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
