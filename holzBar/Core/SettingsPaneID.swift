//
//  SettingsPaneID.swift
//  holzBar
//

import Foundation

/// The panes of the Settings window in sidebar order. The app maps them to its navigation
/// identifiers; this type holds only what is pure: order, groups and symbols.
nonisolated enum SettingsPaneID: String, CaseIterable, Sendable {
    case layout
    case showingAndHiding
    case shelf
    case profilesAndHistory
    case appearance
    case automation
    case modules
    case general
    case hotkeys
    case advanced
    case about

    /// The panes of the sidebar's first group: the menu bar itself.
    static let menuBarGroup: [SettingsPaneID] = [
        .layout, .showingAndHiding, .shelf, .profilesAndHistory, .appearance, .automation
    ]

    /// The sidebar's second group: the optional modules.
    static let modulesGroup: [SettingsPaneID] = [.modules]

    /// The sidebar's last group: the app.
    static let appGroup: [SettingsPaneID] = [.general, .hotkeys, .advanced, .about]

    /// The SF Symbol of the pane's sidebar row; `nil` for About, which shows the app's logo.
    var symbolName: String? {
        switch self {
        case .layout: "menubar.rectangle"
        case .showingAndHiding: "eye"
        case .shelf: "tray"
        case .profilesAndHistory: "clock.arrow.circlepath"
        case .appearance: "paintbrush.pointed"
        case .automation: "bolt.badge.automatic"
        case .modules: "puzzlepiece.extension"
        case .general: "switch.2"
        case .hotkeys: "command"
        case .advanced: "wrench.and.screwdriver"
        case .about: nil
        }
    }
}
