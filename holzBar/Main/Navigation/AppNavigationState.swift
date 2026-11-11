//
//  AppNavigationState.swift
//  holzBar
//

import AppKit
import Observation

/// The model for app-wide navigation.
@MainActor
@Observable
final class AppNavigationState {
    var isAppFrontmost = false
    var isSettingsPresented = false
    /// Whether the What's New window is shown.
    var isWhatsNewPresented = false
    var isShelfPresented = false
    var isSearchPresented = false
    /// Whether the panel of a menu bar item group is shown.
    var isItemGroupPanelPresented = false
    var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general
    /// The Settings search. It lives as long as the app, so a jump can open a disclosure or a
    /// module before the pane that holds it exists.
    let settingsSearch = SettingsSearchModel()
    /// Whether the Menu Bar Layout pane shows the clean-up assistant.
    var isTidyUpPresented = false
    /// The item whose rule ("Show Only When…") the Menu Bar Layout pane edits, if any.
    var itemRuleTarget: ItemRuleTarget?

    /// The Settings window, while it exists. Its visibility is ``isSettingsPresented``.
    @ObservationIgnored weak var settingsWindow: NSWindow?
}

/// The menu bar item that a rule is made or edited for.
struct ItemRuleTarget: Identifiable, Equatable {
    /// The item's identity key.
    let key: String
    let name: String

    var id: String { key }
}
