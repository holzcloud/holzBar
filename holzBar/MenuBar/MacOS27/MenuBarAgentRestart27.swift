//
//  MenuBarAgentRestart27.swift
//  holzBar
//

import Cocoa
import OSLog

/// The "Restart Menu Bar" command of holzBar's menu on macOS 27.
///
/// MenuBarAgent can stall on macOS 27. The command asks `NSRunningApplication` to force-quit it;
/// launchd starts it again by itself. holzBar starts no process (the process allowlist and the
/// decision D-07 forbid it), and the restart detection of 1.0.5 then applies the hiding again.
///
/// The command is user-initiated only: it is offered in holzBar's menu (and the palette and
/// Settings) and never to `holzbar://` URL commands, Shortcuts or automation rules. Whether the
/// bar comes back is the probe P3 of plan 93-16, which removes the command if it does not.
@available(macOS 27.0, *)
@MainActor
enum MenuBarAgentRestart27 {
    /// What a call to ``restart(appState:)`` did.
    enum Outcome {
        /// MenuBarAgent was asked to quit.
        case restarted
        /// A restart was asked for less than five seconds ago.
        case tooSoon
        /// `NSRunningApplication` does not see MenuBarAgent.
        case notRunning
        /// macOS refused to quit MenuBarAgent.
        case refused
    }

    private static let logger = Logger(category: "MenuBarAgentRestart27")

    /// MenuBarAgent as `NSRunningApplication` sees it now, or `nil`.
    private static var agent: NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarItemProvider27.menuBarAgentBundleID
        ).first
    }

    /// Whether MenuBarAgent is visible now. A cheap lookup, read only when a surface is built;
    /// the command is offered only while it is true.
    static var isAvailable: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: MenuBarItemProvider27.menuBarAgentBundleID
        ).isEmpty
    }

    /// Restarts MenuBarAgent, after the breaker expects it.
    @discardableResult
    static func restart(appState: AppState) -> Outcome {
        guard appState.concealer27.prepareForManualRestart() else {
            logger.debug("Restart Menu Bar ignored: asked for less than five seconds ago")
            return .tooSoon
        }
        guard let agent else {
            logger.notice("Restart Menu Bar: MenuBarAgent is not visible")
            showFailure()
            return .notRunning
        }
        guard agent.forceTerminate() else {
            logger.notice("Restart Menu Bar: macOS refused to quit MenuBarAgent")
            showFailure()
            return .refused
        }
        return .restarted
    }

    private static func showFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The menu bar could not be restarted.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }
}
