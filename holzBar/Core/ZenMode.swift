//
//  ZenMode.swift
//  holzBar
//

import Foundation

/// Zen mode keeps every hidden menu bar item hidden until it is turned off (THAW-10).
///
/// While it is active, the gestures and rules that would reveal items on their own are
/// refused: hovering, a click on empty menu bar space, scrolling, the reveal rules, URL
/// commands from other apps and items that show when they change. What the user asks for
/// directly still works: clicking holzBar's icon and the section hotkeys.
///
/// The user turns it on and off (``isManual``); holzBar turns it on while the screen is
/// mirrored or shared (``isAutomatic``). It is active while either is on, so the end of a
/// presentation never turns off what the user turned on.
nonisolated struct ZenMode: Equatable, Sendable {
    /// What can reveal hidden items.
    nonisolated enum Trigger: CaseIterable, Sendable {
        /// The pointer rests on empty menu bar space ("Show on hover").
        case hover
        /// A click on empty menu bar space ("Show on click").
        case clickOnEmptyBar
        /// Scrolling in the menu bar ("Show on scroll").
        case scroll
        /// A rule such as "When the battery is low".
        case revealRule
        /// A `holzbar://` URL from another app.
        case urlCommand
        /// An item that shows when it changes.
        case changeReveal
        /// A click on holzBar's icon.
        case holzBarIcon
        /// The hotkey of a section.
        case sectionHotkey
    }

    /// Whether the user turned Zen mode on.
    var isManual = false

    /// Whether holzBar turned Zen mode on because the screen is mirrored or shared.
    var isAutomatic = false

    /// Whether Zen mode is on.
    var isActive: Bool {
        isManual || isAutomatic
    }

    /// Whether the given trigger may reveal hidden items now.
    func allows(_ trigger: Trigger) -> Bool {
        guard isActive else {
            return true
        }
        switch trigger {
        case .holzBarIcon, .sectionHotkey:
            // The user's own request.
            return true
        case .hover, .clickOnEmptyBar, .scroll, .revealRule, .urlCommand, .changeReveal:
            return false
        }
    }

    /// Zen mode after the user toggled it.
    ///
    /// Turning it off ends the automatic part as well, so it goes off even while the screen
    /// is still shared; holzBar turns it on again only when a presentation starts anew.
    func toggled() -> ZenMode {
        if isActive {
            ZenMode(isManual: false, isAutomatic: false)
        } else {
            ZenMode(isManual: true, isAutomatic: isAutomatic)
        }
    }
}
