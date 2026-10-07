//
//  AppDelegate.swift
//  holzBar
//

import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared app state.
    let appState: AppState

    override init() {
        // Must come before the iCloud pull, which reads the copied sync file,
        // and before the app state, which reads the settings.
        MigrationManager.importPreviousSettingsIfNeeded()
        SettingsSync.pullIfNeeded()
        let appState = AppState()
        AppState.current = appState
        self.appState = appState
        super.init()
    }

    // MARK: NSApplicationDelegate Methods

    func application(_ application: NSApplication, open urls: [URL]) {
        // holzbar:// commands from other apps. The scenes never handle them
        // (`HolzBarWindow` matches no external event).
        for url in urls {
            URLCommands.perform(url, appState: appState)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
            // The Edit menu keeps its key equivalents while hidden, so Undo and Redo (the
            // Layout pane and the profiles), Cut, Copy and Paste work in holzBar's windows.
            let isEditMenu = item.submenu?.items.contains { $0.action == Selector(("undo:")) } ?? false
            if isEditMenu {
                item.allowsKeyEquivalentWhenHidden = true
                for subitem in item.submenu?.items ?? [] {
                    subitem.allowsKeyEquivalentWhenHidden = true
                }
            }
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        // After a relaunch, the previous instance may still hold the hotkeys and status
        // items for a moment, so wait until it has quit.
        if
            let pid = Relaunch.previousPID(in: ProcessInfo.processInfo.environment),
            let previous = NSRunningApplication(processIdentifier: pid),
            previous.bundleIdentifier == Bundle.main.bundleIdentifier
        {
            Task {
                await waitUntilTerminated(previous)
                finishLaunching()
            }
        } else {
            finishLaunching()
        }
    }

    /// Waits until the given instance has quit, for at most ``Relaunch/waitTimeout``.
    private func waitUntilTerminated(_ app: NSRunningApplication) async {
        // React to the termination instead of checking it on a timer. The initial value
        // covers an instance that quits before the observation starts.
        let (terminated, continuation) = AsyncStream.makeStream(of: Void.self)
        let observation = app.observe(\.isTerminated, options: [.initial, .new]) { @Sendable _, change in
            if change.newValue == true {
                continuation.yield()
                continuation.finish()
            }
        }

        let didQuit = await SpacingRelaunch.waitUntil(timeout: Relaunch.waitTimeout) {
            for await _ in terminated {
                return
            }
        }

        observation.invalidate()
        continuation.finish()

        if !didQuit, !app.isTerminated {
            let seconds = Relaunch.waitTimeout.components.seconds
            Logger.default.debug(
                """
                The previous instance did not quit within \(seconds, privacy: .public) seconds, \
                so holzBar sets up anyway
                """
            )
        }
    }

    /// Checks for conflicting apps and sets up holzBar.
    private func finishLaunching() {
        // Another menu bar manager would fight holzBar over the same items.
        guard ConflictingApps.resolve() else {
            NSApp.terminate(nil)
            return
        }

        // Depending on the permissions state, either perform setup
        // or prompt to grant permissions.
        switch appState.permissions.permissionsState {
        case .hasAll:
            appState.permissions.logger.debug("Passed all permissions checks")
            appState.performSetup(hasPermissions: true)
        case .hasRequired:
            appState.permissions.logger.debug("Passed required permissions checks")
            appState.performSetup(hasPermissions: true)
        case .missing:
            appState.permissions.logger.debug("Failed required permissions checks")
            appState.performSetup(hasPermissions: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Logger.default.debug("Handling reopen")
        openSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if
            sender.isActive,
            sender.activationPolicy() != .accessory,
            appState.navigationState.isAppFrontmost
        {
            Logger.default.debug("All windows closed - deactivating with accessory activation policy")
            if appState.menuBarManager.isHidingApplicationMenus {
                // Deactivates the same way, and records that the menus are shown again.
                appState.menuBarManager.showApplicationMenus()
            } else {
                appState.deactivate(withPolicy: .accessory)
            }
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if #available(macOS 27.0, *) {
            // Released synchronously, before the process goes, so no application stays hidden.
            appState.concealer27.releaseAllForTermination()
        }
    }

    // MARK: Other Methods

    /// Opens the settings window and activates the app, or the permissions window while
    /// permissions are missing.
    @objc func openSettingsWindow() {
        // Delay makes this more reliable for some reason.
        Task { [appState] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !appState.openPermissionsWindowIfNeeded() else {
                return
            }
            appState.activate(for: .settings)
            appState.openWindow(.settings)
        }
    }
}
