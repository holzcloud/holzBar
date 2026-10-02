//
//  URLCommands.swift
//  holzBar
//

import AppKit
import OSLog

/// Commands that other apps can send to holzIce with `holzice://` URLs, for
/// example from Raycast, Alfred, Shortcuts or a script (jordanbaird/Ice#501).
///
/// - `holzice://toggle/hidden`, `holzice://show/hidden`, `holzice://hide/hidden`
///   (also `always-hidden`)
/// - `holzice://search` – the menu bar item search
/// - `holzice://settings` – the settings window
/// - `holzice://ice-bar/toggle` – turn the holzIce Bar on or off
/// - `holzice://auto-rehide/toggle` – turn auto-rehide on or off
/// - `holzice://application-menus/toggle`
/// - `holzice://profile/<name>` – apply a saved layout profile
@MainActor
enum URLCommands {
    private static let logger = Logger(category: "URLCommands")

    /// Starts receiving `holzice://` URLs.
    static func register(appState: AppState) {
        Handler.shared.appState = appState
        NSAppleEventManager.shared().setEventHandler(
            Handler.shared,
            andSelector: #selector(Handler.handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Performs the command in the given URL.
    static func perform(_ url: URL, appState: AppState) {
        guard url.scheme?.lowercased() == "holzice", let host = url.host()?.lowercased() else {
            logger.warning("Ignoring URL \(url.absoluteString, privacy: .public)")
            return
        }
        let arguments = url.pathComponents.filter { $0 != "/" }.map { $0.removingPercentEncoding ?? $0 }
        let manager = appState.menuBarManager
        logger.notice("Performing \(url.absoluteString, privacy: .public)")

        func section() -> MenuBarSection? {
            switch arguments.first?.lowercased() {
            case "always-hidden", "alwayshidden": manager.section(withName: .alwaysHidden)
            default: manager.section(withName: .hidden)
            }
        }

        switch host {
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
        case "ice-bar":
            appState.settings.general.useIceBar.toggle()
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
            logger.warning("Unknown command \(host, privacy: .public)")
        }
    }

    /// Receives the Apple events that carry the URLs.
    private final class Handler: NSObject {
        static let shared = Handler()

        weak var appState: AppState?

        @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
            guard
                let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
                let url = URL(string: string)
            else {
                return
            }
            MainActor.assumeIsolated {
                guard let appState else {
                    return
                }
                URLCommands.perform(url, appState: appState)
            }
        }
    }
}
