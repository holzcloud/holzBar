//
//  DisplayBehavior.swift
//  holzBar
//

import Foundation

/// What a display does with the hidden menu bar items, chosen per display.
///
/// The display under the pointer wins: the behaviour is read where the pointer is, and changes
/// when the pointer moves to another display.
///
/// The raw values are stored in the user's settings; a new case goes at the end and no value is
/// ever reused.
nonisolated enum DisplayBehavior: Int, CaseIterable, Identifiable, Sendable {
    /// Hidden items behave as the settings say everywhere else.
    case standard = 0
    /// Every section stays shown while the pointer is on the display: nothing is hidden there,
    /// whatever hides it elsewhere (a click on empty space, rehiding, a hotkey).
    case showEverything = 1
    /// The hidden items stay hidden while the pointer is on the display: what would reveal them
    /// on their own (hovering, a click on empty space, scrolling, rules) is refused, as in Zen
    /// mode. Clicking holzBar's icon and the section hotkeys still reveal them.
    case collapse = 2

    var id: Int { rawValue }

    /// The choice stored as `raw`, or the standard one when the number names none: a settings
    /// file or an older or newer holzBar may have written anything.
    static func stored(_ raw: Int) -> DisplayBehavior {
        DisplayBehavior(rawValue: raw) ?? .standard
    }

    /// Whether a section may be hidden now.
    var allowsHiding: Bool {
        self != .showEverything
    }

    /// Whether the given trigger may reveal hidden items now. Collapsing refuses what reveals
    /// by itself, just as Zen mode does (`ZenMode.allows(_:)`).
    func allows(_ trigger: ZenMode.Trigger) -> Bool {
        switch self {
        case .standard, .showEverything:
            true
        case .collapse:
            ZenMode(isManual: true).allows(trigger)
        }
    }

    /// What to do to the sections when the pointer moves from a display with one behaviour to a
    /// display with another.
    nonisolated enum Action: Equatable, Sendable {
        case none
        /// Show every section.
        case showAll
        /// Hide every section.
        case hideAll
    }

    /// The action for a change of behaviour. Nothing happens for the same behaviour twice.
    ///
    /// Leaving a display that showed everything tucks the items away again; leaving one that
    /// collapsed them changes nothing, since they are hidden already.
    static func action(from previous: DisplayBehavior, to new: DisplayBehavior) -> Action {
        guard previous != new else {
            return .none
        }
        switch new {
        case .showEverything: return .showAll
        case .collapse: return .hideAll
        case .standard: return previous == .showEverything ? .hideAll : .none
        }
    }
}

/// The behaviour chosen for each display, by the display's UUID.
///
/// Only a display with a choice other than the standard one is stored, so an empty value means
/// every display behaves as usual and costs nothing.
nonisolated struct DisplayBehaviors: Equatable, Sendable {
    /// The most displays that keep a choice. A settings file is data from outside, and displays
    /// come and go, so the list is bounded.
    static let maximumCount = 32

    /// The longest display identifier kept, in UTF-8 bytes. A display UUID has 36.
    static let maximumIdentifierLength = 64

    private(set) var choices: [String: DisplayBehavior]

    init() {
        choices = [:]
    }

    /// Reads the stored form: a dictionary of display UUID to the raw value of a behaviour.
    /// Anything that is not a whole number naming a behaviour other than the standard one, a
    /// key that is empty or too long, and everything past the limit is dropped.
    init(stored: [String: Any]) {
        var choices = [String: DisplayBehavior]()
        for key in stored.keys.sorted() {
            guard
                choices.count < Self.maximumCount,
                Self.isValidIdentifier(key),
                let number = stored[key] as? NSNumber,
                number.doubleValue == number.doubleValue.rounded(),
                let raw = Int(exactly: number.doubleValue),
                let behavior = DisplayBehavior(rawValue: raw),
                behavior != .standard
            else {
                continue
            }
            choices[key] = behavior
        }
        self.choices = choices
    }

    /// The stored form.
    var stored: [String: Int] {
        choices.mapValues(\.rawValue)
    }

    /// Whether no display has a choice, so nothing needs to watch the pointer.
    var isEmpty: Bool {
        choices.isEmpty
    }

    /// The behaviour of a display; the standard one for a display without a choice or `nil`.
    func behavior(of display: String?) -> DisplayBehavior {
        display.flatMap { choices[$0] } ?? .standard
    }

    /// Sets the behaviour of a display. The standard one forgets the display; a new display
    /// past the limit is refused.
    mutating func set(_ behavior: DisplayBehavior, for display: String) {
        guard Self.isValidIdentifier(display) else {
            return
        }
        if behavior == .standard {
            choices[display] = nil
        } else if choices[display] != nil || choices.count < Self.maximumCount {
            choices[display] = behavior
        }
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= maximumIdentifierLength
    }
}
