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
/// `holzice://` URLs and the `ice-bar` command still work.
@MainActor
enum URLCommands {
    private static let logger = Logger(category: "URLCommands")

    /// The URL schemes holzBar accepts: `holzbar://` is holzBar's own, and
    /// `holzice://` keeps scripts written for holzIce working.
    private static let schemes: Set<String> = ["holzbar", "holzice"]

    /// Starts receiving `holzbar://` and `holzice://` URLs.
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
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme), let host = url.host()?.lowercased() else {
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
