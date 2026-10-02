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
            logger.warning("Ignoring URL \(url.absoluteString, privacy: .public)")
            return
        }
        let arguments = command.arguments
        let manager = appState.menuBarManager
        logger.notice("Performing \(url.absoluteString, privacy: .public)")

        func section() -> MenuBarSection? {
            switch arguments.first?.lowercased() {
            case "always-hidden", "alwayshidden": manager.section(withName: .alwaysHidden)
            default: manager.section(withName: .hidden)
            }
        }

        switch command.name {
        case "toggle":
            section()?.toggle()
        case "show":
            section()?.show()
            manager.showOnHoverAllowed = false
        case "hide":
            section()?.hide()
        case "search":
            manager.searchPanel.toggle()
        case "settings":
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        case "shelf", "ice-bar":
            appState.settings.general.useShelf.toggle()
        case "auto-rehide":
            appState.settings.general.autoRehide.toggle()
        case "application-menus":
            manager.toggleApplicationMenus()
        case "profile":
            guard let name = arguments.first else {
                return
            }
            appState.profiles.apply(named: name)
        default:
            logger.warning("Unknown command \(command.name, privacy: .public)")
        }
    }
}
