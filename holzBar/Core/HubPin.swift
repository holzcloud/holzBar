//
//  HubPin.swift
//  holzBar
//

import Foundation

/// Whether the open Notch hub is pinned, and which closes a pinned hub refuses (D-12, D-27).
///
/// A pinned hub stays open on whatever module is in front. Only the two passive closes are
/// vetoed, a click outside the hub and the pointer leaving it. Every explicit command still
/// closes it, so a pinned hub can never be impossible to close: Esc (one press unpins and closes
/// it; the earlier wording of the UI contract is superseded by D-27), the hotkey, a gesture, a
/// change of Space or of displays, opening Settings and the module being switched off. Every
/// closing that is allowed unpins.
///
/// The pin is state of the open hub only: it is never stored, also not across closing. The value
/// does no I/O.
nonisolated struct HubPin: Equatable, Sendable {
    /// Why the hub is about to close.
    nonisolated enum CloseReason: Equatable, Sendable {
        /// A click outside the hub. Passive.
        case outsideClick
        /// The pointer left the hub. Passive.
        case pointerLeft
        /// The Esc key.
        case escape
        /// The hub's hotkey.
        case hotkey
        /// A gesture that closes the hub.
        case gesture
        /// The user switched to another Space.
        case spaceChange
        /// The displays changed.
        case displayChange
        /// Settings opened.
        case settings
        /// The Notch hub module was switched off.
        case moduleOff
    }

    /// Whether the hub is pinned open.
    private(set) var isPinned = false

    /// A click on the pin button: pins an unpinned hub and unpins a pinned one (which stays open).
    mutating func toggle() {
        isPinned.toggle()
    }

    /// Clears the pin; changes nothing when it is not set.
    mutating func unpin() {
        isPinned = false
    }

    /// Whether the hub may close for the reason. A pinned hub refuses the passive closes and
    /// stays pinned; every other reason is allowed and unpins.
    mutating func allowsClose(_ reason: CloseReason) -> Bool {
        guard isPinned else {
            return true
        }
        switch reason {
        case .outsideClick, .pointerLeft:
            return false
        case .escape, .hotkey, .gesture, .spaceChange, .displayChange, .settings, .moduleOff:
            unpin()
            return true
        }
    }
}
