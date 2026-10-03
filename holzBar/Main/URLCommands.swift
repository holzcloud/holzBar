//
//  URLCommands.swift
//  holzBar
//

import AppKit
import OSLog

/// Commands that other apps can send to holzBar with `holzbar://` URLs, for
/// example from Raycast, Alfred, Shortcuts or a script (jordanbaird/Ice#501).
///
/// - `holzbar://toggle/hidden`, `holzbar://show/hidden`, `holzbar://hide/hidden`
///   (also `always-hidden`)
/// - `holzbar://search` – the menu bar item search
/// - `holzbar://settings` – the settings window
/// - `holzbar://shelf/toggle` – turn the holzBar Shelf on or off
/// - `holzbar://auto-rehide/toggle` – turn auto-rehide on or off
/// - `holzbar://application-menus/toggle`
/// - `holzbar://profile/<name>` – apply a saved layout profile
///
/// `ice-bar` still works as another name for `shelf`.
///
/// The URLs arrive through the app delegate's `application(_:open:)`.
@MainActor
enum URLCommands {
    private static let logger = Logger(category: "URLCommands")

    /// The URL scheme holzBar accepts.
    private static let scheme = "holzbar"

    /// Performs the command in the given URL.
    static func perform(_ url: URL, appState: AppState) {
        guard let command = URLCommand(url: url, scheme: scheme) else {
            // The URL itself is not logged: its path can hold a profile name.
            logger.warning("Ignoring a URL that is not a holzBar command")
            return
        }
        let manager = appState.menuBarManager
        // Only the command is logged, never the URL or its arguments (profile names).
        logger.notice("Performing \(command.name, privacy: .public)")

        func section(_ name: URLCommand.Section) -> MenuBarSection? {
            switch name {
            case .hidden: manager.section(withName: .hidden)
            case .alwaysHidden: manager.section(withName: .alwaysHidden)
            }
        }

        switch command.action {
        case .toggle(let name):
            section(name)?.toggle()
        case .show(let name):
            section(name)?.show()
            manager.showOnHoverAllowed = false
        case .hide(let name):
            section(name)?.hide()
        case .search:
            manager.searchPanel.toggle()
        case .settings:
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        case .toggleShelf:
            appState.settings.general.useShelf.toggle()
        case .toggleAutoRehide:
            appState.settings.general.autoRehide.toggle()
        case .toggleApplicationMenus:
            manager.toggleApplicationMenus()
        case .applyProfile(let name):
            appState.profiles.apply(named: name)
        case .unknown:
            logger.warning("Unknown command \(command.name, privacy: .private)")
        }
    }
}
