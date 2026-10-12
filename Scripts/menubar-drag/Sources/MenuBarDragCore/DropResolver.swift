//
//  DropResolver.swift
//  holzBar
//

import CoreGraphics

/// Where a drop on the menu bar lands, as far as holzBar's intent is concerned.
public enum DropTarget: Sendable, Equatable {
    /// Just left of the item with this id (`LayoutBarMoves.move(_:to: .leftOfItem(_))`).
    case leftOf(String)

    /// Just right of the item with this id (`LayoutBarMoves.move(_:to: .rightOfItem(_))`).
    case rightOf(String)

    /// Into a section (`LayoutBarMoves.setSection(of:to:appState:)`).
    case section(BarSection)
}

/// A drop zone that holzBar's overlay draws for a section, in CoreGraphics global coordinates.
public struct DropZone: Sendable, Equatable {
    public let section: BarSection
    public let frame: CGRect

    public init(section: BarSection, frame: CGRect) {
        self.section = section
        self.frame = frame
    }
}

/// The call holzBar would make for a drop, which is what the Layout pane does for the same drop.
public enum DropIntent: Sendable, Equatable {
    /// Before macOS 27: `LayoutBarMoves.move(_:to:appState:actionName:)` next to a neighbour.
    case move(item: String, target: DropTarget)

    /// `LayoutBarMoves.setSection(of:to:appState:)`: before macOS 27 the move next to the section's
    /// control item, on macOS 27 `Concealer27.setSection(_:for:)` for the owning application.
    case setSection(item: String, owner: String, section: BarSection)

    /// On macOS 27 the Layout pane cannot reorder items within one section: macOS does, and holzBar
    /// has no call to make (`LayoutBarPaddingView.performDragOperation` fails such a drop).
    case macOSOrders(item: String)

    /// The drop is not something holzBar moves.
    case refused(reason: String)

    public var isRefused: Bool {
        if case .refused = self {
            return true
        }
        return false
    }

    /// The call as one line of the report: the intent strings are the contract between the probe
    /// and the spike's result, and name holzBar's real functions
    /// (`holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift`, `holzBar/MenuBar/MacOS27/Concealer27.swift`).
    ///
    /// - Parameters:
    ///   - shownID: Writes an item id the way the report shows it.
    ///   - shownOwner: Writes an owner the way the report shows it.
    public func rendered(
        generation: Generation,
        shownID: (String) -> String,
        shownOwner: (String) -> String
    ) -> String {
        switch self {
        case .move(let item, let target):
            switch target {
            case .leftOf(let neighbour):
                return "LayoutBarMoves.move(\(shownID(item)), to: .leftOfItem(\(shownID(neighbour))))"
            case .rightOf(let neighbour):
                return "LayoutBarMoves.move(\(shownID(item)), to: .rightOfItem(\(shownID(neighbour))))"
            case .section(let section):
                return "LayoutBarMoves.setSection(of: \(shownID(item)), to: .\(section.rawValue))"
            }
        case .setSection(let item, let owner, let section):
            let call = "LayoutBarMoves.setSection(of: \(shownID(item)), to: .\(section.rawValue))"
            guard generation == .macOS27 else {
                return call
            }
            return call + " -> Concealer27.setSection(.\(section.rawValue), for: \(shownOwner(owner)))"
        case .macOSOrders:
            return "none: macOS 27 orders items within a section"
        case .refused(let reason):
            return "refused: \(reason)"
        }
    }
}

/// Turns the point where an item was dropped into the call holzBar would make for it.
public enum DropResolver {
    /// How far below the bar a release still counts as on it, in points.
    private static let tolerance: CGFloat = 4

    /// The target of a drop at `point`, in this order: nothing below the bar; a zone that contains
    /// the point; on macOS 27 holzBar's icon (holzBar draws no dividers there, so the icon is the
    /// way to name the hidden section); the counted item under the point, by its halves; else the
    /// nearest counted item on the right, else the nearest on the left. The dragged item is never
    /// its own target.
    public static func target(
        forDropAt point: CGPoint,
        draggedID: String,
        in snapshot: BarSnapshot,
        zones: [DropZone]
    ) -> DropTarget? {
        guard point.y <= snapshot.barMaxY + tolerance else {
            return nil
        }
        if let zone = zones.first(where: { $0.frame.contains(point) }) {
            return .section(zone.section)
        }
        let others = snapshot.items.filter { $0.counts && $0.id != draggedID }
        if snapshot.generation == .macOS27,
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
    /// section is set), and a drop among the visible items of an application saved as hidden sets
    /// the visible section, while any other neighbour drop is left to macOS.
    ///
    /// - Parameter currentSection: The section the item is in, `nil` when the probe cannot know it
    ///   (on macOS 27 it cannot read holzBar's saved layout).
    public static func intent(
        for target: DropTarget?,
        dragged: BarItem,
        in snapshot: BarSnapshot,
        currentSection: BarSection?
    ) -> DropIntent {
        guard dragged.kind == .app else {
            return .refused(reason: "only app items are moved")
        }
        guard let target else {
            return .refused(reason: "dropped outside the bar")
        }
        switch target {
        case .section(let section):
            return .setSection(item: dragged.id, owner: dragged.owner, section: section)
        case .leftOf, .rightOf:
            guard snapshot.generation == .macOS27 else {
                return .move(item: dragged.id, target: target)
            }
            if currentSection == .hidden || currentSection == .alwaysHidden {
                return .setSection(item: dragged.id, owner: dragged.owner, section: .visible)
            }
            return .macOSOrders(item: dragged.id)
        }
    }

    /// Whether macOS put the item where the target says, as the final read shows it: for a
    /// neighbour target its place in the order, for a section target the section by position.
    ///
    /// - Returns: `false` when the dragged item or the neighbour is missing; `nil` for a section
    ///   target when the section cannot be told from positions (macOS 27).
    public static func landed(_ target: DropTarget, draggedID: String, in after: BarSnapshot) -> Bool? {
        let order = after.orderedIDs()
        switch target {
        case .leftOf(let neighbour):
            guard let index = order.firstIndex(of: draggedID), let other = order.firstIndex(of: neighbour) else {
                return false
            }
            return index + 1 == other
        case .rightOf(let neighbour):
            guard let index = order.firstIndex(of: draggedID), let other = order.firstIndex(of: neighbour) else {
                return false
            }
            return index - 1 == other
        case .section(let section):
            guard let item = after.item(withID: draggedID), item.counts else {
                return false
            }
            return after.positionalSection(of: item).map { $0 == section }
        }
    }
}
