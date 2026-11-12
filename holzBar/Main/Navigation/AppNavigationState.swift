//
//  AppNavigationState.swift
//  holzBar
//

import AppKit
import Observation

/// The model for app-wide navigation.
/// What Layout shows: the bars as the menu bar does, or a list of every item (D-08).
nonisolated enum LayoutPaneView: Hashable {
    case bars
    case list
}

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
    /// The pane the Settings window shows. Choosing a pane in any way ends a running search, so a
    /// jump to a pane is never hidden behind results.
    var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general {
        didSet { settingsSearch.clear() }
    }
    /// The Settings search. It lives as long as the app, so a jump can open a disclosure or a
    /// module before the pane that holds it exists.
    let settingsSearch = SettingsSearchModel()
    /// Whether the Menu Bar Layout pane shows the clean-up assistant.
    var isTidyUpPresented = false
    /// Whether Layout shows the bars or the list; lasts for the session, never stored (D-09).
    var layoutView = LayoutPaneView.bars
    /// The text of Layout's filter; lasts for the session, never stored (D-09).
    var layoutFilter = ""
    /// The item whose rule ("Show Only When…") the Menu Bar Layout pane edits, if any.
    var itemRuleTarget: ItemRuleTarget?

    /// The Settings window, while it exists. Its visibility is ``isSettingsPresented``.
    @ObservationIgnored weak var settingsWindow: NSWindow?

    /// Leads from a found setting to its row: selects its pane (which ends the search), opens the
    /// disclosure and the module that hold it, and sets the row as the target the pane host
    /// scrolls to and highlights. It does not open the window; callers do that.
    func revealSetting(_ entry: SettingsEntry) {
        settingsNavigationIdentifier = SettingsNavigationIdentifier(entry.pane)
        if let disclosure = entry.disclosure {
            settingsSearch.openDisclosures.insert(disclosure)
        }
        if let module = entry.module {
            settingsSearch.openModule = module
        }
        settingsSearch.revealTarget = entry.id
        settingsSearch.clear()
    }

    /// Opens the Modules pane with one module's area open and scrolled into view. The module's
    /// row carries the catalogue id `modules.<id>`. It does not open the window; callers do that.
    func openModuleSettings(_ moduleID: String) {
        settingsNavigationIdentifier = .modules
        settingsSearch.openModule = moduleID
        settingsSearch.revealTarget = "modules.\(moduleID)"
        settingsSearch.clear()
    }
}

/// The menu bar item that a rule is made or edited for.
struct ItemRuleTarget: Identifiable, Equatable {
    /// The item's identity key.
    let key: String
    let name: String

    var id: String { key }
}
