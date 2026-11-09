//
//  CommandDragSection.swift
//  holzBar
//

import Foundation

// On macOS the geometry members of CGRect and CGPoint live in CoreGraphics, which the app's
// member import visibility requires; on Linux Foundation provides them.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Decides what a Command-drag of an app's item in the macOS 27 menu bar means for its section.
///
/// On macOS 27 the order of the bar no longer says which section an app is in, and holzBar draws
/// no dividers, so holzBar's icon is the only boundary: an item that crosses it from right to
/// left is hidden, one that crosses it from left to right is visible. A reorder on one side of
/// the icon leaves the app alone. The functions here are pure: two bars (at the press and after
/// the drop settled) and two points go in, a section or a reason comes out.
nonisolated enum CommandDragSection {
    /// Which side of holzBar's icon an item is on.
    nonisolated enum Side: Equatable, Sendable {
        case left
        case right
    }

    /// Why a drop sets no section. The raw value is a fixed word for the last-command-drag line of
    /// Copy Diagnostics; it never carries a name or a position.
    nonisolated enum Reason: String, Equatable, Sendable {
        /// The pointer moved less than ``CommandDragSection/movementThreshold``: a click.
        case noMovement = "no movement"
        /// The dragged item is not an application's.
        case notAnAppItem = "not an app item"
        /// holzBar's icon is not drawn, so there is no boundary.
        case noIcon = "no icon"
        /// The dragged item is no longer in the bar after the drop.
        case itemGone = "item gone"
        /// The drop is on holzBar's icon, where macOS decides.
        case onIcon = "on the icon"
        /// The item stayed on its side of the icon.
        case crossedNothing = "crossed nothing"
        /// The item has no layout key (applied by the app layer).
        case noKey = "no key"
        /// The press was on another display than the active menu bar (applied by the app layer).
        case otherDisplay = "other display"
        /// A later press replaced this gesture (applied by the app layer).
        case superseded = "superseded"
    }

    /// What a drop means.
    nonisolated enum Decision: Equatable, Sendable {
        /// Set the section of the item's application; only visible or hidden.
        case set(MenuBarDrop.Section)
        case ignore(Reason)
    }

    /// Why an application's section is not free.
    nonisolated enum Lock: String, Equatable, Sendable {
        /// A rule controls the item.
        case rule
        /// The user pinned the item.
        case pinned
        /// macOS keeps the item in place (a numbered system item).
        case system
    }

    /// What holzBar does with a decision.
    nonisolated enum Outcome: Equatable, Sendable {
        /// Write the new section.
        case apply(from: MenuBarDrop.Section, to: MenuBarDrop.Section)
        /// The section stays; the lock is the reason for a notice.
        case keep(Lock)
        /// Nothing to do.
        case nothing
    }

    /// How far the pointer must move horizontally between the press and the release for the drag
    /// to count, in points. Less is a click.
    static let movementThreshold: CGFloat = 4

    /// How far around holzBar's icon a release still counts as on it, in points; the same margin
    /// ``MenuBarDrop`` uses for a drop on the icon.
    static let iconMargin: CGFloat = MenuBarDrop.iconMargin

    /// The side of holzBar's icon an item is on, comparing the centres within one bar.
    ///
    /// - Returns: `nil` when the item is not counted (4 points wide or narrower) or the bar has no
    ///   usable icon: the counted holzBar icon.
    static func side(of id: UInt32, in bar: MenuBarDrop.Bar) -> Side? {
        guard let icon = icon(in: bar),
              let item = bar.items.first(where: { $0.id == id && $0.counts }) else {
            return nil
        }
        return item.frame.midX < icon.frame.midX ? .left : .right
    }

    /// What a drop means for an application's item.
    ///
    /// The order of the checks: no movement, not an app item, item gone, no icon, on the icon,
    /// crossed nothing; then the side after the drop gives the section. The side is read from the
    /// order within each bar, never from the pointer, because macOS 27 slides items aside while
    /// one is dragged across them. The pointer only tells whether the release was on the icon.
    ///
    /// - Parameters:
    ///   - press: The bar when the button went down.
    ///   - settled: The bar after the drop settled, `nil` when it could not be read.
    static func decide(
        draggedID: UInt32,
        press: MenuBarDrop.Bar,
        pressPoint: CGPoint,
        release: CGPoint,
        settled: MenuBarDrop.Bar?
    ) -> Decision {
        guard abs(release.x - pressPoint.x) >= movementThreshold else {
            return .ignore(.noMovement)
        }
        guard let dragged = press.items.first(where: { $0.id == draggedID }) else {
            return .ignore(.itemGone)
        }
        guard dragged.kind == .app else {
            return .ignore(.notAnAppItem)
        }
        guard let settled, settled.items.contains(where: { $0.id == draggedID && $0.counts }) else {
            return .ignore(.itemGone)
        }
        guard let before = side(of: draggedID, in: press), let after = side(of: draggedID, in: settled) else {
            return .ignore(.noIcon)
        }
        let settledIcon = icon(in: settled)?.frame
        let zone = MenuBarDrop.resolve(
            forDropAt: release,
            draggedID: draggedID,
            in: press,
            settledIconFrame: settledIcon
        ).zone
        switch zone {
        case .icon, .iconMargin, .iconShifted, .iconSettled:
            return .ignore(.onIcon)
        default:
            break
        }
        guard before != after else {
            return .ignore(.crossedNothing)
        }
        return .set(after == .left ? .hidden : .visible)
    }

    /// What a drop means for an item macOS does not move (a pinned or numbered system item): the
    /// bar after the drop would never show a crossing, so the pointer alone decides. The side
    /// before is the dragged item's own, the side after is the release point's; a release on the
    /// icon, within ``iconMargin``, is left to macOS.
    ///
    /// - Parameter draggedFrame: The frame of the pressed item in `press`.
    static func decideFixed(
        draggedFrame: CGRect,
        press: MenuBarDrop.Bar,
        pressPoint: CGPoint,
        release: CGPoint
    ) -> Decision {
        guard abs(release.x - pressPoint.x) >= movementThreshold else {
            return .ignore(.noMovement)
        }
        guard let icon = icon(in: press)?.frame else {
            return .ignore(.noIcon)
        }
        guard !((icon.minX - iconMargin)...(icon.maxX + iconMargin)).contains(release.x) else {
            return .ignore(.onIcon)
        }
        let before: Side = draggedFrame.midX < icon.midX ? .left : .right
        let after: Side = release.x < icon.midX ? .left : .right
        guard before != after else {
            return .ignore(.crossedNothing)
        }
        return .set(after == .left ? .hidden : .visible)
    }

    /// What holzBar does with a decision. A lock wins over every set, so a rule, a pin or macOS
    /// keeps its item; a section the app already has, or hidden for an always-hidden app (which
    /// is deeper than hidden and stays where it is), is nothing to do.
    static func outcome(for decision: Decision, current: MenuBarDrop.Section, lock: Lock?) -> Outcome {
        guard case .set(let target) = decision else {
            return .nothing
        }
        if let lock {
            return .keep(lock)
        }
        if target == current || (target == .hidden && current == .alwaysHidden) {
            return .nothing
        }
        return .apply(from: current, to: target)
    }

    /// One line about a command-drag from a fixed vocabulary of words and numbers: how long it
    /// waited for the bar to settle, how many reads it took, the decision and what became of it.
    /// It never contains a name or a position.
    static func summary(waitedMilliseconds: Int, reads: Int, decision: Decision, outcome: Outcome) -> String {
        let waited = "waited \(max(0, waitedMilliseconds)) ms"
        let count = max(0, reads)
        let readWord = "\(count) \(count == 1 ? "read" : "reads")"
        let result: String
        switch decision {
        case .ignore(let reason):
            result = "ignored: \(reason.rawValue)"
        case .set(let section):
            let target: String = switch section {
            case .visible: "visible"
            case .hidden: "hidden"
            case .alwaysHidden: "always hidden"
            }
            let what: String = switch outcome {
            case .apply: "applied"
            case .keep(let lock): "kept: \(lock.rawValue)"
            case .nothing: "no change"
            }
            result = "set \(target), \(what)"
        }
        return [waited, readWord, result].joined(separator: ", ")
    }

    /// The counted holzBar icon of a bar: the anchor of every decision.
    private static func icon(in bar: MenuBarDrop.Bar) -> MenuBarDrop.Item? {
        bar.items.first { $0.kind == .holzBarIcon && $0.counts }
    }
}

/// What a command-drag told the user in Menu Bar Layout.
nonisolated struct CommandDragNotice: Equatable, Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// The application's section was set; Undo puts `from` back.
        case set(from: MenuBarDrop.Section, to: MenuBarDrop.Section)
        /// The section stayed because it is not free.
        case kept(CommandDragSection.Lock)
    }

    /// The notice's key for an item macOS keeps in place, which has no layout key and no name.
    static let systemKey = "CommandDragSystemItem"

    /// The application's layout key: one notice per application.
    let id: String
    /// The application's name, cleaned; empty for the nameless system notice.
    let itemName: String
    let kind: Kind

    /// The notice of an application, its name made safe to show; the key stands in for an empty name.
    static func make(key: String, name: String, kind: Kind) -> CommandDragNotice {
        CommandDragNotice(id: key, itemName: ItemRuleNotices.cleanedName(name, fallback: key), kind: kind)
    }

    /// The notice of a numbered system item macOS keeps in place: it has no name.
    static func system() -> CommandDragNotice {
        CommandDragNotice(id: systemKey, itemName: "", kind: .kept(.system))
    }
}

/// The list of command-drag notices.
nonisolated enum CommandDragNotices {
    /// The most notices that are kept.
    static let limit = 10

    /// The notices with `notice` first. An application has one notice: an earlier one for the
    /// same key is replaced, so Undo always undoes the latest drop. At most `limit` are kept.
    static func adding(_ notice: CommandDragNotice, to notices: [CommandDragNotice], limit: Int = CommandDragNotices.limit) -> [CommandDragNotice] {
        Array(([notice] + notices.filter { $0.id != notice.id }).prefix(limit))
    }
}
