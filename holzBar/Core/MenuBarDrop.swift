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
/// next to a neighbour; on macOS 27 a drop on holzBar's icon or on the open Shelf sets the
/// application's section to hidden, and a drop among the other items is left to macOS, which
/// orders the items within a section.
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

        /// The refusal in fixed words.
        var word: String {
            switch self {
            case .notAnAppItem: "not an app item"
            case .outsideTheBar: "outside the bar"
            }
        }
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

        /// The intent in the fixed words of ``MenuBarDrop/summary(generation:zone:intent:result:)``.
        var word: String {
            switch self {
            case .move, .macOSOrders:
                "order"
            case .setSection(_, let section):
                switch section {
                case .visible: "show"
                case .hidden: "hide"
                case .alwaysHidden: "always hide"
                }
            case .refused(let refusal):
                "refused, \(refusal.word)"
            }
        }
    }

    /// Where a drop landed, as far as the decision is concerned. The raw value is the word the
    /// last-drop line of Copy Diagnostics uses; it never carries a name or a position.
    nonisolated enum Zone: String, Equatable, Sendable {
        /// Inside the icon's frame at the press.
        case icon
        /// Within the margin around that frame.
        case iconMargin
        /// On the icon where it slides to while the dragged item crosses it.
        case iconShifted
        /// On the icon where the settled bar has it.
        case iconSettled
        /// On the open Shelf.
        case shelf
        /// On another item of the bar.
        case item
        /// In a gap of the bar.
        case gap
        /// Not on the bar and not on the Shelf.
        case outsideBar
    }

    /// The target of a drop and where it landed.
    nonisolated struct Resolution: Equatable, Sendable {
        let target: Target?
        let zone: Zone
    }

    /// What became of the intent.
    nonisolated enum Outcome: String, Equatable, Sendable {
        case applied
        case notApplied = "not applied"
        case noChange = "no change"
    }

    /// How far below the bar a release still counts as on it, in points.
    private static let tolerance: CGFloat = 4

    /// How far around the holzBar icon a release still counts as on it, in points.
    static let iconMargin: CGFloat = 6

    /// The room between two items, which the icon slides by on top of the dragged item's width.
    static let gapEstimate: CGFloat = 4

    /// The target of a drop at `point` and where it landed, in this order. Below the bar, on
    /// macOS 27, the open Shelf's zone is the hidden section and anything else is nothing. In or
    /// near the bar, on macOS 27, holzBar's icon (holzBar draws no dividers there, so the icon
    /// names the hidden section) in four places: its frame at the press, that frame widened by
    /// ``iconMargin``, that frame slid by the dragged item's width toward the side the item came
    /// from (macOS 27 moves items aside while one is dragged across them) and `settledIconFrame`,
    /// the frame read after the drop; the last three widened by the margin. Then the counted
    /// item under the point, by its halves; else the nearest counted item on the right, else the
    /// nearest on the left. The dragged item is never its own target.
    ///
    /// - Parameters:
    ///   - settledIconFrame: The icon's frame in the bar as it is after the drop, if known.
    ///   - shelfZone: The open Shelf's frame, extended up to the bar's bottom edge, if one is open.
    static func resolve(
        forDropAt point: CGPoint,
        draggedID: UInt32,
        in bar: Bar,
        settledIconFrame: CGRect? = nil,
        shelfZone: CGRect? = nil
    ) -> Resolution {
        if bar.generation == .macOS27, point.y > bar.barMaxY, let shelfZone, shelfZone.contains(point) {
            return Resolution(target: .section(.hidden), zone: .shelf)
        }
        guard point.y <= bar.barMaxY + tolerance else {
            return Resolution(target: nil, zone: .outsideBar)
        }
        let others = bar.items.filter { $0.counts && $0.id != draggedID }
        if bar.generation == .macOS27, let zone = iconZone(at: point.x, draggedID: draggedID, in: bar, settled: settledIconFrame) {
            return Resolution(target: .section(.hidden), zone: zone)
        }
        if let under = others.first(where: { ($0.frame.minX...$0.frame.maxX).contains(point.x) }) {
            return Resolution(target: point.x < under.frame.midX ? .leftOf(under.id) : .rightOf(under.id), zone: .item)
        }
        if let right = others.filter({ $0.frame.minX > point.x }).min(by: { $0.frame.minX < $1.frame.minX }) {
            return Resolution(target: .leftOf(right.id), zone: .gap)
        }
        if let left = others.filter({ $0.frame.maxX < point.x }).max(by: { $0.frame.maxX < $1.frame.maxX }) {
            return Resolution(target: .rightOf(left.id), zone: .gap)
        }
        return Resolution(target: nil, zone: .outsideBar)
    }

    /// Which zone of holzBar's icon an x lies in, if any; only the x range matters.
    private static func iconZone(at x: CGFloat, draggedID: UInt32, in bar: Bar, settled: CGRect?) -> Zone? {
        guard let icon = bar.items.first(where: { $0.kind == .holzBarIcon && $0.counts })?.frame else {
            return nil
        }
        func range(_ frame: CGRect, margin: CGFloat) -> ClosedRange<CGFloat> {
            (frame.minX - margin)...(frame.maxX + margin)
        }
        if range(icon, margin: 0).contains(x) {
            return .icon
        }
        if range(icon, margin: iconMargin).contains(x) {
            return .iconMargin
        }
        if let dragged = bar.items.first(where: { $0.id == draggedID })?.frame {
            let slide = dragged.width + gapEstimate
            let dx: CGFloat? = if dragged.minX > icon.maxX {
                slide
            } else if dragged.maxX < icon.minX {
                -slide
            } else {
                nil
            }
            if let dx, range(icon.offsetBy(dx: dx, dy: 0), margin: iconMargin).contains(x) {
                return .iconShifted
            }
        }
        if let settled, range(settled, margin: iconMargin).contains(x) {
            return .iconSettled
        }
        return nil
    }

    /// One line about a drop, from a fixed vocabulary only: the generation, the zone, the intent
    /// and what became of it. It never contains a name, a title or a position.
    ///
    /// - Parameter intent: `nil` when the drop led to no intent.
    static func summary(generation: Generation, zone: Zone, intent: Intent?, result: Outcome) -> String {
        let generationWord = generation == .macOS27 ? "macOS 27" : "before 27"
        return [generationWord, zone.rawValue, intent?.word ?? "none", result.rawValue].joined(separator: ", ")
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
