//
//  HotkeyAction.swift
//  holzBar
//

import Foundation

/// An action a hotkey performs.
///
/// The raw values are stored in the `Hotkeys` setting (see ``HotkeyStorage``) and were
/// Ice's, so imported and synced hotkeys keep working. Never change them. What each action
/// does is in `HotkeyActionPerform.swift`.
nonisolated enum HotkeyAction: String, Codable, CaseIterable {
    // Menu Bar Sections
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    case showHiddenSectionTemporarily = "ShowHiddenSectionTemporarily"

    // Menu Bar Items
    case searchMenuBarItems = "SearchMenuBarItems"

    // Other

    /// The stored string keeps the name that earlier versions of the app
    /// stored this hotkey under, so imported settings keep working.
    case enableShelf = "EnableIceBar"
    case toggleApplicationMenus = "ToggleApplicationMenus"
    case toggleAutoRehide = "ToggleAutoRehide"

    // Added by holzBar; new actions go at the end.
    case toggleZenMode = "ToggleZenMode"
    case showItemHints = "ShowItemHints"
}
