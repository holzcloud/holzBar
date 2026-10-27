//
//  ShelfContents.swift
//  holzBar
//

import Foundation

/// The part of the menu bar a tile of the holzBar Shelf belongs to.
nonisolated enum ShelfGroup: Int, Equatable, Sendable {
    /// A visible item that the notch covers, which the Shelf lists too.
    case visible = 0
    /// The hidden section.
    case hidden = 1
    /// The always-hidden section.
    case alwaysHidden = 2
}

/// One tile of the holzBar Shelf.
nonisolated struct ShelfTile: Equatable, Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// A menu bar item that is on the bar now.
        case item(windowID: UInt32)
        /// The tile that opens and closes the always-hidden items; `count` is how many it holds.
        case fold(count: Int, isOpen: Bool)
        /// An application that is not running and has a hidden item remembered.
        case closedApp(bundleID: String)
        /// The thin line between two groups of a row.
        case divider
    }

    let kind: Kind
    let group: ShelfGroup
    /// What a search matches: the item's or application's name. Empty for the fold and a divider.
    let name: String

    /// A stable identity: the same tile has the same identifier from one frame to the next.
    var id: String {
        switch kind {
        case .item(let windowID): "item-\(windowID)"
        case .fold: "fold"
        case .closedApp(let bundleID): "app-\(bundleID)"
        case .divider: "divider-\(group.rawValue)"
        }
    }

    /// Whether the keyboard can stop on the tile: every tile but a divider.
    var isNavigable: Bool {
        if case .divider = kind {
            return false
        }
        return true
    }

    /// Whether a search looks at the tile: an item and a closed application.
    var isSearchable: Bool {
        switch kind {
        case .item, .closedApp: true
        case .fold, .divider: false
        }
    }
}

/// Which tiles the holzBar Shelf shows, and in which order.
///
/// The Shelf of the hidden section lists, from left to right as the menu bar does, the
/// always-hidden items behind one fold tile (or open, after a divider), the visible items that
/// the notch covers and the hidden items. An application that is not running goes with the
/// section it is remembered in.
nonisolated enum ShelfContents {
    /// A menu bar item that is on the bar now.
    nonisolated struct Item: Equatable, Sendable {
        let windowID: UInt32
        let name: String

        init(windowID: UInt32, name: String) {
            self.windowID = windowID
            self.name = name
        }
    }

    /// An application that is not running.
    nonisolated struct ClosedApp: Equatable, Sendable {
        let bundleID: String
        let name: String

        init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    nonisolated struct Input: Equatable, Sendable {
        /// Visible items that the notch covers.
        var covered = [Item]()
        var hidden = [Item]()
        var alwaysHidden = [Item]()
        var closedHidden = [ClosedApp]()
        var closedAlwaysHidden = [ClosedApp]()
        /// Whether the always-hidden items sit behind a fold tile. When they do not, they are
        /// listed as the Shelf's own group: the Shelf of the always-hidden section.
        var foldsAlwaysHidden = false
        /// Whether the fold is open; only read when `foldsAlwaysHidden` is on.
        var isFoldOpen = false
        /// Whether a divider goes between two groups: in a row, where groups sit side by side.
        var showsDividers = false
        /// Whether the closed applications of a group come before its items: in a row, which
        /// is read from the right, so the items on the bar stay next to the end it starts from.
        var closedFirst = false

        init() { }
    }

    /// The tiles, in the order they are drawn.
    static func tiles(_ input: Input) -> [ShelfTile] {
        let alwaysHiddenCount = input.alwaysHidden.count + input.closedAlwaysHidden.count
        var groups = [[ShelfTile]]()

        if input.foldsAlwaysHidden {
            if alwaysHiddenCount > 0 {
                let fold = ShelfTile(kind: .fold(count: alwaysHiddenCount, isOpen: input.isFoldOpen), group: .alwaysHidden, name: "")
                var tiles = [fold]
                if input.isFoldOpen {
                    tiles += groupTiles(.alwaysHidden, items: input.alwaysHidden, closed: input.closedAlwaysHidden, closedFirst: input.closedFirst)
                }
                groups.append(tiles)
            }
        } else {
            groups.append(groupTiles(.alwaysHidden, items: input.alwaysHidden, closed: input.closedAlwaysHidden, closedFirst: input.closedFirst))
        }
        groups.append(groupTiles(.visible, items: input.covered, closed: [], closedFirst: false))
        groups.append(groupTiles(.hidden, items: input.hidden, closed: input.closedHidden, closedFirst: input.closedFirst))

        var result = [ShelfTile]()
        for tiles in groups where !tiles.isEmpty {
            if input.showsDividers, let last = result.last, let next = tiles.first, last.group != next.group {
                result.append(ShelfTile(kind: .divider, group: last.group, name: ""))
            }
            result += tiles
        }
        return result
    }

    /// The tiles of one group: its items and its closed applications.
    private static func groupTiles(
        _ group: ShelfGroup,
        items: [Item],
        closed: [ClosedApp],
        closedFirst: Bool
    ) -> [ShelfTile] {
        let live = items.map { ShelfTile(kind: .item(windowID: $0.windowID), group: group, name: $0.name) }
        let dimmed = closed.map { ShelfTile(kind: .closedApp(bundleID: $0.bundleID), group: group, name: $0.name) }
        return closedFirst ? dimmed + live : live + dimmed
    }
}
