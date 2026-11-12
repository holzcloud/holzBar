//
//  SettingsNavigationIdentifier.swift
//  holzBar
//

import SwiftUI

/// The navigation identifier type for the "Settings" interface: the eleven panes in sidebar order.
///
/// The case names `menuBarLayout` and `menuBarAppearance` stay as they are because the menu bar
/// code observes `.menuBarLayout` (it lifts concealment and photographs items while the layout
/// pane is open); only the titles in the raw values changed.
nonisolated enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case menuBarLayout = "Layout"
    case showingAndHiding = "Showing & Hiding"
    case shelf = "holzBar Shelf"
    case profilesAndHistory = "Profiles & History"
    case menuBarAppearance = "Appearance"
    case automation = "Automation"
    case modules = "Modules"
    case general = "General"
    case hotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    /// The panes about the menu bar, the first group of the sidebar.
    static let menuBarGroup: [SettingsNavigationIdentifier] =
        SettingsPaneID.menuBarGroup.map(SettingsNavigationIdentifier.init)

    /// The pane that lists the optional modules, the second group of the sidebar.
    static let modulesGroup: [SettingsNavigationIdentifier] =
        SettingsPaneID.modulesGroup.map(SettingsNavigationIdentifier.init)

    /// The panes about holzBar itself, the third group of the sidebar.
    static let appGroup: [SettingsNavigationIdentifier] =
        SettingsPaneID.appGroup.map(SettingsNavigationIdentifier.init)

    /// The identifier of a pane.
    init(_ pane: SettingsPaneID) {
        switch pane {
        case .layout: self = .menuBarLayout
        case .showingAndHiding: self = .showingAndHiding
        case .shelf: self = .shelf
        case .profilesAndHistory: self = .profilesAndHistory
        case .appearance: self = .menuBarAppearance
        case .automation: self = .automation
        case .modules: self = .modules
        case .general: self = .general
        case .hotkeys: self = .hotkeys
        case .advanced: self = .advanced
        case .about: self = .about
        }
    }

    /// The pane this identifier stands for.
    var pane: SettingsPaneID {
        switch self {
        case .menuBarLayout: .layout
        case .showingAndHiding: .showingAndHiding
        case .shelf: .shelf
        case .profilesAndHistory: .profilesAndHistory
        case .menuBarAppearance: .appearance
        case .automation: .automation
        case .modules: .modules
        case .general: .general
        case .hotkeys: .hotkeys
        case .advanced: .advanced
        case .about: .about
        }
    }

    /// The title of the pane. The literals are written out so `strings-check.py` sees the titles,
    /// which it cannot through the raw value.
    var localized: LocalizedStringKey {
        switch self {
        case .menuBarLayout: "Layout"
        case .showingAndHiding: "Showing & Hiding"
        case .shelf: "holzBar Shelf"
        case .profilesAndHistory: "Profiles & History"
        case .menuBarAppearance: "Appearance"
        case .automation: "Automation"
        case .modules: "Modules"
        case .general: "General"
        case .hotkeys: "Hotkeys"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// The symbol of the pane's sidebar row, or the holzBar logo for About.
    @MainActor var iconResource: IconResource {
        if let name = pane.symbolName {
            .systemSymbol(name)
        } else {
            .assetCatalog(.logoStroke)
        }
    }
}
