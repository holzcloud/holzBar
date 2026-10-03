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
///
/// Another app can ask with a `holzbar://zen` URL (``requested(byURL:)``): it may turn Zen
/// mode on, but never ends the automatic part, and turning it off asks the user first
/// (`URLCommand.Action.decision(zenMode:)`). Shortcuts actions act like the user's own
/// toggle, because the user built the shortcut.
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

    /// What another app asks for with a `holzbar://zen` URL.
    nonisolated enum Request: Equatable, Sendable {
        /// `holzbar://zen/on`.
        case turnOn
        /// `holzbar://zen/off`.
        case turnOff
        /// `holzbar://zen` or `holzbar://zen/toggle`: off while on, on while off.
        case toggle
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

    /// Zen mode after another app asked for `request` with a URL.
    ///
    /// Only the user's part (``isManual``) changes: a URL never ends the automatic part, so
    /// Zen mode stays on while the screen is shared.
    func requested(byURL request: Request) -> ZenMode {
        let turnsOn = switch request {
        case .turnOn: true
        case .turnOff: false
        case .toggle: !isActive
        }
        return ZenMode(isManual: turnsOn, isAutomatic: isAutomatic)
    }
}
