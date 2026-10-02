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
        self.appState = AppState()
        super.init()
    }

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Initial chore work.
        NSSplitViewItem.swizzle()
        MigrationManager(appState: appState).migrateAll()
        URLCommands.register(appState: appState)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the main menu's items to add additional space to the
        // menu bar when we are the focused app.
        for item in NSApp.mainMenu?.items ?? [] {
            item.isHidden = true
        }

        // Allow hiding the mouse while the app is in the background
        // to make menu bar item movement less jarring.
        Bridging.setConnectionProperty(true, forKey: "SetsCursorInBackground")

        #if DEBUG
        // Don't perform setup if running as a preview.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif

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
            appState.deactivate(withPolicy: .accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: Other Methods

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        // Delay makes this more reliable for some reason.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [appState] in
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }
}
