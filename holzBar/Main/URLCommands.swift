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
/// - `holzbar://shelf/toggle` – turn the holzBar Shelf on or off; a setting that lasts
///   and syncs, so holzBar asks first
/// - `holzbar://auto-rehide/toggle` – turn auto-rehide on or off; a setting that lasts
///   and syncs, so holzBar asks first
/// - `holzbar://application-menus/toggle` – hides or shows the application menus;
///   nothing persistent
/// - `holzbar://zen/on`, `holzbar://zen/off`, `holzbar://zen/toggle` – Zen mode; turning
///   it on only hides, turning it off asks first, and while the screen is shared it stays on
/// - `holzbar://profile/<name>` – apply a saved layout profile; rearranges items, so
///   holzBar asks first
///
/// Any app can open these URLs without the user knowing, and a web page can once the
/// browser has asked, so `URLCommand.Action.decision(zenMode:)` decides what runs at once,
/// what needs the user's answer and what is refused. While Zen mode is on, no URL reveals
/// hidden items or changes a setting. The questions show no text from the URL, at most
/// one is open, and after the user declines one, holzBar asks nothing for a while
/// (`URLPrompt`). Shortcuts actions (App Intents) run without the question, because the
/// user built them.
///
/// `ice-bar` still works as another name for `shelf`.
///
/// The URLs arrive through the app delegate's `application(_:open:)`.
@MainActor
enum URLCommands {
    private static let logger = Logger(category: "URLCommands")

    /// The URL scheme holzBar accepts.
    private static let scheme = "holzbar"

    /// Lets one question be open at a time, and none for a while after a declined one.
    private static var promptGate = URLPrompt.Gate()

    /// A question to the user, and what holzBar does when they agree.
    private struct Confirmation {
        let message: String
        let detail: String
        let confirmTitle: String
        let perform: () -> Void
    }

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

        switch command.action.decision(zenMode: manager.zenMode) {
        case .perform:
            perform(command.action, appState: appState)
        case .refuse:
            logger.notice("Ignored: Zen mode")
        case .ask:
            guard
                let confirmation = confirmation(for: command.action, appState: appState),
                ask(confirmation, appState: appState)
            else {
                return
            }
            // The screen may have started to be shared while the question was open.
            guard command.action.decision(zenMode: manager.zenMode) != .refuse else {
                logger.notice("Ignored: Zen mode")
                return
            }
            confirmation.perform()
        }
    }

    /// Performs an action that needs no answer from the user.
    private static func perform(_ action: URLCommand.Action, appState: AppState) {
        let manager = appState.menuBarManager

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

        switch action {
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
        case .toggleApplicationMenus:
            manager.toggleApplicationMenus()
        case .zenMode(let request):
            // Turns Zen mode on, or leaves it off; turning it off is asked first.
            manager.setZenModeFromURL(manager.zenMode.requested(byURL: request))
        case .toggleShelf, .toggleAutoRehide, .applyProfile:
            // Never performed without the user's answer (`confirmation(for:appState:)`).
            logger.error("Ignored: a command that needs the user's answer")
        case .unknown:
            logger.warning("Unknown command")
        }
    }

    /// The question for an action that needs the user's answer, or `nil` when there is
    /// nothing to ask, such as a profile that does not exist.
    ///
    /// The question shows only what holzBar stores, never text from the URL: a profile's
    /// own name, cleaned up and shortened (`URLPrompt.displayName(_:)`). What the user
    /// agrees to is fixed when the question is asked: the setting gets the value the
    /// question names, even if it changed meanwhile.
    private static func confirmation(for action: URLCommand.Action, appState: AppState) -> Confirmation? {
        let manager = appState.menuBarManager
        let general = appState.settings.general
        let settingDetail = String(localized: "Another app asked holzBar to change this setting.")
        switch action {
        case .applyProfile(let name):
            guard let profile = appState.profiles.profile(named: name) else {
                logger.notice("Ignored: no layout profile with that name")
                return nil
            }
            let storedName = profile.name
            let displayName = URLPrompt.displayName(storedName)
            return Confirmation(
                message: String(localized: "Apply the layout profile \u{201C}\(displayName)\u{201D}?"),
                detail: String(localized: "Another app asked holzBar to rearrange your menu bar."),
                confirmTitle: String(localized: "Apply"),
                perform: {
                    appState.profiles.apply(named: storedName)
                }
            )
        case .toggleShelf:
            let turnsOn = !general.useShelf
            return Confirmation(
                message: turnsOn
                    ? String(localized: "Turn on the holzBar Shelf?")
                    : String(localized: "Turn off the holzBar Shelf?"),
                detail: settingDetail,
                confirmTitle: turnsOn ? String(localized: "Turn On") : String(localized: "Turn Off"),
                perform: {
                    general.useShelf = turnsOn
                }
            )
        case .toggleAutoRehide:
            let turnsOn = !general.autoRehide
            return Confirmation(
                message: turnsOn
                    ? String(localized: "Turn on auto-rehide?")
                    : String(localized: "Turn off auto-rehide?"),
                detail: settingDetail,
                confirmTitle: turnsOn ? String(localized: "Turn On") : String(localized: "Turn Off"),
                perform: {
                    general.autoRehide = turnsOn
                }
            )
        case .zenMode:
            return Confirmation(
                message: String(localized: "Turn off Zen mode?"),
                detail: String(localized: "Another app asked holzBar to turn off Zen mode. Hidden items could then be shown."),
                confirmTitle: String(localized: "Turn Off"),
                perform: {
                    manager.setZenModeFromURL(manager.zenMode.requested(byURL: .turnOff))
                }
            )
        case .toggle, .show, .hide, .search, .settings, .toggleApplicationMenus, .unknown:
            return nil
        }
    }

    /// Asks the user whether another app may do what it asked.
    ///
    /// holzBar comes to the front without a Dock icon for the question. The buttons sit
    /// where the Human Interface Guidelines put them, the action on the right and Cancel to
    /// its left; as another app asked, the action takes a click: Return answers nothing, and
    /// Escape answers Cancel. While a question is open, or for a while after the user
    /// declined one, holzBar asks nothing and ignores the command (`URLPrompt.Gate`).
    ///
    /// - Returns: Whether the user agreed.
    private static func ask(_ confirmation: Confirmation, appState: AppState) -> Bool {
        guard promptGate.begin(at: .now) else {
            logger.notice("Ignored: a question is open or was just declined")
            return false
        }
        appState.activate(for: .settings)
        let alert = NSAlert()
        alert.messageText = confirmation.message
        alert.informativeText = confirmation.detail
        let confirm = alert.addButton(withTitle: confirmation.confirmTitle)
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        // NSAlert gives the first button Return; this question has no default answer.
        confirm.keyEquivalent = ""
        // Escape in every language, not only for the English title "Cancel".
        cancel.keyEquivalent = "\u{1B}"
        let approved = alert.runModal() == .alertFirstButtonReturn
        promptGate.end(approved: approved, at: .now)
        if !approved {
            logger.notice("A command from another app was declined")
        }
        return approved
    }
}
