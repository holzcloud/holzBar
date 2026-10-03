//
//  LayoutKeys.swift
//  holzBar
//

import Foundation

/// What the keys do in the Menu Bar Layout pane (THAW-14).
///
/// The arrows move the focus: Left and Right between the items of a section, Up and Down
/// between the sections. Option with an arrow moves the focused item: Left and Right one
/// place within its section (refused where macOS orders the items, on macOS 27), Up and
/// Down to the neighbouring section. Command-1, 2 and 3 move it to the visible, hidden
/// and always-hidden section. Return or Space opens the item's menu.
nonisolated enum LayoutKeys {
    /// Virtual key codes (`kVK_*` of Carbon's `Events.h`).
    nonisolated enum Key {
        static let returnKey = 36
        static let keypadEnter = 76
        static let space = 49
        static let leftArrow = 123
        static let rightArrow = 124
        static let downArrow = 125
        static let upArrow = 126
        static let one = 18
        static let two = 19
        static let three = 20
    }

    /// The section an item moves to.
    nonisolated enum SectionTarget: Equatable, Sendable {
        /// The section on the right, toward the visible one.
        case previous
        /// The section on the left, toward the always-hidden one.
        case next
        case visible
        case hidden
        case alwaysHidden
    }

    /// What a key does.
    nonisolated enum Command: Equatable, Sendable {
        /// Moves the focus by the given steps: `dx` within a section, `dy` between sections.
        case focus(dx: Int, dy: Int)
        /// Moves the focused item by one place within its section.
        case moveWithinSection(Int)
        /// Moves the focused item to another section.
        case moveToSection(SectionTarget)
        /// Opens the focused item's menu.
        case openMenu
        /// Says why the key does nothing here.
        case refused(String)
    }

    /// Why an item cannot move within its section on macOS 27.
    static let macOSOrdersItems = "macOS orders the items within each section."

    /// The command for a key, or `nil` for a key the Layout pane leaves alone.
    ///
    /// - Parameters:
    ///   - keyCode: The key's virtual key code.
    ///   - modifiers: The modifier keys held.
    ///   - itemsKeepOrder: Whether items can be ordered within a section (before macOS 27).
    static func command(keyCode: Int, modifiers: Modifiers, itemsKeepOrder: Bool = true) -> Command? {
        let modifiers = modifiers.subtracting(.shift)
        switch (keyCode, modifiers) {
        case (Key.leftArrow, []):
            return .focus(dx: -1, dy: 0)
        case (Key.rightArrow, []):
            return .focus(dx: 1, dy: 0)
        case (Key.upArrow, []):
            return .focus(dx: 0, dy: -1)
        case (Key.downArrow, []):
            return .focus(dx: 0, dy: 1)
        case (Key.leftArrow, .option):
            return itemsKeepOrder ? .moveWithinSection(-1) : .refused(macOSOrdersItems)
        case (Key.rightArrow, .option):
            return itemsKeepOrder ? .moveWithinSection(1) : .refused(macOSOrdersItems)
        case (Key.upArrow, .option):
            return .moveToSection(.previous)
        case (Key.downArrow, .option):
            return .moveToSection(.next)
        case (Key.one, .command):
            return .moveToSection(.visible)
        case (Key.two, .command):
            return .moveToSection(.hidden)
        case (Key.three, .command):
            return .moveToSection(.alwaysHidden)
        case (Key.returnKey, []), (Key.keypadEnter, []), (Key.space, []):
            return .openMenu
        default:
            return nil
        }
    }

    /// A place in the Layout pane: a section's row and an item's index in it.
    nonisolated struct Position: Equatable, Sendable {
        var row: Int
        var index: Int
    }

    /// Where the focus goes for a focus command.
    ///
    /// Within a row the focus stops at either end. Between rows it skips empty rows and
    /// lands on the item nearest the same index; at the first or last row it stays.
    ///
    /// - Parameters:
    ///   - position: The focused place.
    ///   - command: The command; anything but `.focus` keeps the position.
    ///   - rowCounts: The number of items in each row, top to bottom.
    static func focusTarget(from position: Position, command: Command, rowCounts: [Int]) -> Position {
        guard
            case .focus(let dx, let dy) = command,
            rowCounts.indices.contains(position.row)
        else {
            return position
        }
        if dy == 0 {
            let count = rowCounts[position.row]
            guard count > 0 else {
                return position
            }
            return Position(row: position.row, index: min(max(position.index + dx, 0), count - 1))
        }
        var row = position.row + (dy > 0 ? 1 : -1)
        while rowCounts.indices.contains(row) {
            let count = rowCounts[row]
            if count > 0 {
                return Position(row: row, index: min(max(position.index, 0), count - 1))
            }
            row += dy > 0 ? 1 : -1
        }
        return position
    }

    /// The index of the section an item moves to, or `nil` when it stays.
    ///
    /// - Parameters:
    ///   - target: Where the command moves it.
    ///   - current: The index of the item's section (0 visible, 1 hidden, 2 always hidden).
    ///   - sectionCount: The number of enabled sections.
    static func sectionIndex(for target: SectionTarget, from current: Int, sectionCount: Int) -> Int? {
        let index = switch target {
        case .previous: current - 1
        case .next: current + 1
        case .visible: 0
        case .hidden: 1
        case .alwaysHidden: 2
        }
        guard index != current, index >= 0, index < sectionCount else {
            return nil
        }
        return index
    }
}
