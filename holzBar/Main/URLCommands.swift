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
///   (also `always-hidden`) – changes nothing persistent
/// - `holzbar://search` – the menu bar item search; changes nothing persistent
/// - `holzbar://settings` – the settings window; changes nothing persistent
/// - `holzbar://shelf/toggle` – turn the holzBar Shelf on or off; a setting the same
///   command flips back
/// - `holzbar://auto-rehide/toggle` – turn auto-rehide on or off; a setting the same
///   command flips back
/// - `holzbar://application-menus/toggle` – hides or shows the application menus;
///   nothing persistent
/// - `holzbar://zen/toggle` – turns Zen mode on or off; it only hides, and while it is
///   on, `show` and `toggle` of a hidden section are ignored
/// - `holzbar://profile/<name>` – apply a saved layout profile; rearranges items, so
///   holzBar asks first (`URLCommand.Action.needsConfirmation`)
///
/// Any app can open these URLs without the user knowing, so the only command that
/// rearranges the menu bar needs the user's answer. Shortcuts actions (App Intents) run
/// without the question, because the user built them.
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

        // Zen mode keeps hidden items hidden; another app cannot reveal them.
        func isRefusedByZenMode(_ target: MenuBarSection) -> Bool {
            guard target.isHidden, !manager.zenMode.allows(.urlCommand) else {
                return false
            }
            logger.notice("Ignored: Zen mode")
            return true
        }

        switch command.action {
        case .toggle(let name):
            guard let target = section(name), !isRefusedByZenMode(target) else {
                return
            }
            target.toggle()
        case .show(let name):
            guard let target = section(name), !isRefusedByZenMode(target) else {
                return
            }
            target.show()
            manager.showOnHoverAllowed = false
        case .hide(let name):
            section(name)?.hide()
        case .search:
            manager.searchPanel.toggle()
        case .settings:
            appState.activate(for: .settings)
            appState.openWindow(.settings)
        case .toggleShelf:
            appState.settings.general.useShelf.toggle()
        case .toggleAutoRehide:
            appState.settings.general.autoRehide.toggle()
        case .toggleApplicationMenus:
            manager.toggleApplicationMenus()
        case .toggleZenMode:
            manager.toggleZenMode()
        case .applyProfile(let name):
            guard !command.action.needsConfirmation || confirmProfile(named: name, appState: appState) else {
                logger.notice("Applying a layout profile from a URL was cancelled")
                return
            }
            appState.profiles.apply(named: name)
        case .unknown:
            logger.warning("Unknown command \(command.name, privacy: .private)")
        }
    }

    /// Asks whether another app may apply the layout profile with the given name.
    ///
    /// holzBar comes to the front without a Dock icon for the question; Cancel is the
    /// default answer and the answer to Escape.
    ///
    /// - Returns: Whether the user chose Apply.
    private static func confirmProfile(named name: String, appState: AppState) -> Bool {
        appState.activate(for: .settings)
        let alert = NSAlert()
        alert.messageText = "Apply the layout profile \u{201C}\(name)\u{201D}?"
        alert.informativeText = "Another app asked holzBar to rearrange your menu bar."
        // The first button is the default one (Return).
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Apply")
        // Escape answers Cancel as well: it ends the alert without Apply.
        let escapeMonitor = EventMonitor.local(for: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }
            NSApp.abortModal()
            return nil
        }
        escapeMonitor.start()
        defer {
            escapeMonitor.stop()
        }
        return alert.runModal() == .alertSecondButtonReturn
    }
}
