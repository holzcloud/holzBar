//
//  MenuBarDrop.swift
//  holzBar
//

import Foundation

// On macOS the geometry members of CGRect and CGPoint live in CoreGraphics, which the app's
// member import visibility requires; on Linux Foundation provides them.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Turns the point where an item was dropped on the menu bar into the call holzBar makes for it.
///
/// Every drop sends the same intent as a move in the Layout pane. Before macOS 27 that is a move
/// next to a neighbour; on macOS 27 the Layout pane only assigns applications to sections and
/// macOS orders the items within one, so only a section is an intent there.
nonisolated enum MenuBarDrop {
    /// How the menu bar is built on the macOS that runs holzBar.
    ///
    /// Before macOS 27 every item is a window of its own; on macOS 27 the whole bar is drawn by
    /// one process and holzBar's dividers are never drawn.
    nonisolated enum Generation: Equatable, Sendable {
        case before27
        case macOS27
    }

    /// A section of the menu bar.
    nonisolated enum Section: Int, Equatable, Sendable {
        case visible
        case hidden
        case alwaysHidden
    }

    /// One item of the bar.
    nonisolated struct Item: Equatable, Sendable {
        /// What an item is, as far as a drop is concerned.
        nonisolated enum Kind: Equatable, Sendable {
            /// An application's item that can be moved and hidden.
            case app
            /// An item of macOS, or one an application cannot hide.
            case system
            /// holzBar's icon, the item that shows and hides the hidden section.
            case holzBarIcon
            /// holzBar's divider in front of the hidden section.
            case hiddenDivider
            /// holzBar's divider in front of the always-hidden section.
            case alwaysHiddenDivider
            /// Any other item of holzBar's, such as a widget.
            case holzBarOther
        }

        /// The item's window identifier (a synthetic one on macOS 27).
        let id: UInt32
        let kind: Kind
        /// The item's frame in screen coordinates, origin top left.
        let frame: CGRect

        init(id: UInt32, kind: Kind, frame: CGRect) {
            self.id = id
            self.kind = kind
            self.frame = frame
        }

        /// Whether the item takes room in the bar: holzBar's collapsed items and folded items are
        /// 4 points wide or narrower.
        var counts: Bool {
            frame.width > 4
        }
    }

    /// The menu bar of one display at one moment.
    nonisolated struct Bar: Equatable, Sendable {
        let generation: Generation
        let displayBounds: CGRect
        /// The bottom edge of the bar, in screen coordinates.
        let barMaxY: CGFloat
        /// Every item, sorted by its left edge.
        let items: [Item]

        init(generation: Generation, displayBounds: CGRect, barMaxY: CGFloat, items: [Item]) {
            self.generation = generation
            self.displayBounds = displayBounds
            self.barMaxY = barMaxY
            self.items = items.sorted { $0.frame.minX < $1.frame.minX }
        }

        /// The counted item under a point, only inside the bar strip of the display.
        func item(at point: CGPoint) -> Item? {
            guard displayBounds.contains(point), point.y <= barMaxY else {
                return nil
            }
            return items.first { $0.counts && ($0.frame.minX...$0.frame.maxX).contains(point.x) }
        }
    }

    /// Where a drop lands, as far as holzBar's intent is concerned.
    nonisolated enum Target: Equatable, Sendable {
        /// Just left of the item with this identifier.
        case leftOf(UInt32)
        /// Just right of the item with this identifier.
        case rightOf(UInt32)
        /// Into a section.
        case section(Section)
    }

    /// Why a drop is not something holzBar acts on.
    nonisolated enum Refusal: Equatable, Sendable {
        /// The dragged item is not an application's.
        case notAnAppItem
        /// The drop is not on the bar.
        case outsideTheBar
    }

    /// The call holzBar makes for a drop.
    nonisolated enum Intent: Equatable, Sendable {
        /// Before macOS 27: move the item next to a neighbour.
        case move(item: UInt32, target: Target)
        /// Set the section of the item's application.
        case setSection(item: UInt32, section: Section)
        /// On macOS 27 macOS orders the items within a section and holzBar has nothing to record.
        case macOSOrders(item: UInt32)
        /// The drop is not something holzBar acts on.
        case refused(Refusal)
    }

    /// How far below the bar a release still counts as on it, in points.
    private static let tolerance: CGFloat = 4

    /// The target of a drop at `point`, in this order: nothing below the bar; on macOS 27 holzBar's
    /// icon (holzBar draws no dividers there, so the icon names the hidden section); the counted
    /// item under the point, by its halves; else the nearest counted item on the right, else the
    /// nearest on the left. The dragged item is never its own target.
    static func target(forDropAt point: CGPoint, draggedID: UInt32, in bar: Bar) -> Target? {
        guard point.y <= bar.barMaxY + tolerance else {
            return nil
        }
        let others = bar.items.filter { $0.counts && $0.id != draggedID }
        if bar.generation == .macOS27,
           others.contains(where: { $0.kind == .holzBarIcon && ($0.frame.minX...$0.frame.maxX).contains(point.x) }) {
            return .section(.hidden)
        }
        if let under = others.first(where: { ($0.frame.minX...$0.frame.maxX).contains(point.x) }) {
            return point.x < under.frame.midX ? .leftOf(under.id) : .rightOf(under.id)
        }
        if let right = others.filter({ $0.frame.minX > point.x }).min(by: { $0.frame.minX < $1.frame.minX }) {
            return .leftOf(right.id)
        }
        if let left = others.filter({ $0.frame.maxX < point.x }).max(by: { $0.frame.maxX < $1.frame.maxX }) {
            return .rightOf(left.id)
        }
        return nil
    }

    /// The intent for a drop, following the Layout pane: before macOS 27 a neighbour moves the item
    /// there; on macOS 27 only a drop into another section does something (the application's
    /// section is set), and a drop among the visible items of an application that is hidden sets
    /// the visible section, while any other neighbour drop is left to macOS.
    ///
    /// - Parameter currentSection: The section the dragged item is in, `nil` when unknown.
    static func intent(for target: Target?, dragged: Item, in bar: Bar, currentSection: Section?) -> Intent {
        guard dragged.kind == .app else {
            return .refused(.notAnAppItem)
        }
        guard let target else {
            return .refused(.outsideTheBar)
        }
        switch target {
        case .section(let section):
            return .setSection(item: dragged.id, section: section)
        case .leftOf, .rightOf:
            guard bar.generation == .macOS27 else {
                return .move(item: dragged.id, target: target)
            }
            if currentSection == .hidden || currentSection == .alwaysHidden {
                return .setSection(item: dragged.id, section: .visible)
            }
            return .macOSOrders(item: dragged.id)
        }
    }

    /// Where macOS placed an item, read from the bar after the drop: left of its right neighbour,
    /// else right of its left one. This is the rule of a drop in the Layout pane, so a move to it
    /// finds the item already there and only records the move.
    ///
    /// - Returns: `nil` when the item is not counted or has no counted neighbour.
    static func placement(of draggedID: UInt32, in bar: Bar) -> Target? {
        let counted = bar.items.filter(\.counts)
        guard let index = counted.firstIndex(where: { $0.id == draggedID }) else {
            return nil
        }
        if counted.indices.contains(index + 1) {
            return .leftOf(counted[index + 1].id)
        }
        if counted.indices.contains(index - 1) {
            return .rightOf(counted[index - 1].id)
        }
        return nil
    }
}
