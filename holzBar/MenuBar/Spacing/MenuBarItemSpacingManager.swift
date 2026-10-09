//
//  MenuBarItemSpacingManager.swift
//  holzBar
//

import Cocoa
import OSLog

/// Manager for menu bar item spacing.
@MainActor
final class MenuBarItemSpacingManager {
    /// An error thrown when the spacing preferences could not be saved.
    private struct SaveError: LocalizedError {
        var errorDescription: String? {
            "The menu bar item spacing could not be saved."
        }
    }

    /// An error that groups multiple failed app relaunches.
    private struct GroupedRelaunchError: LocalizedError {
        let failedApps: [String]

        var errorDescription: String? {
            let seconds = SpacingRelaunch.quitTimeout.components.seconds
            return "The following applications did not quit within \(seconds) seconds and were not restarted:\n"
                + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
        }
    }

    /// Logger for the menu bar item spacing manager.
    private let logger = Logger(category: "MenuBarItemSpacingManager")

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

    /// Writes the spacing preferences for the current ``offset`` to the current host's
    /// global domain, the same domain `defaults -currentHost -globalDomain` uses.
    ///
    /// An offset of 0 removes the preferences, which restores macOS's default.
    private func writeSpacingPreferences() throws {
        let value = SpacingRelaunch.spacingPreferenceValue(forOffset: offset).map { NSNumber(value: $0) }
        for key in SpacingRelaunch.spacingPreferenceKeys {
            CFPreferencesSetValue(
                key as CFString,
                value,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw SaveError()
        }
    }

    /// Asks the given app to quit and waits until it has, for at most
    /// ``SpacingRelaunch/quitTimeout``.
    ///
    /// An app that is still running then is left alone; it is never force terminated.
    ///
    /// - Returns: Whether the app has quit.
    private func quit(_ app: NSRunningApplication) async -> Bool {
        if app.isTerminated {
            logger.debug("Application \"\(app.logString, privacy: .private(mask: .hash))\" is already terminated")
            return true
        }

        // React to the app's termination instead of checking it on a timer. The initial
        // value covers an app that quits before the observation starts.
        let (terminated, continuation) = AsyncStream.makeStream(of: Void.self)
        let observation = app.observe(\.isTerminated, options: [.initial, .new]) { @Sendable _, change in
            if change.newValue == true {
                continuation.yield()
                continuation.finish()
            }
        }

        logger.debug("Signaling application \"\(app.logString, privacy: .private(mask: .hash))\" to quit")
        app.terminate()

        let didQuit = await SpacingRelaunch.waitUntil(timeout: SpacingRelaunch.quitTimeout) {
            for await _ in terminated {
                return
            }
        }

        observation.invalidate()
        continuation.finish()

        if didQuit || app.isTerminated {
            logger.debug("Application \"\(app.logString, privacy: .private(mask: .hash))\" terminated successfully")
            return true
        }
        let seconds = SpacingRelaunch.quitTimeout.components.seconds
        logger.debug(
            """
            Application \"\(app.logString, privacy: .private(mask: .hash))\" did not quit within \
            \(seconds, privacy: .public) seconds, so it is left running
            """
        )
        return false
    }

    /// Asynchronously launches the app at the given URL, unless it respawned on its own.
    ///
    /// - Parameters:
    ///   - applicationURL: The app's location.
    ///   - bundleIdentifier: The app's bundle identifier.
    ///   - oldPID: The process that was quit; while it is still listed it does not count as
    ///     the app running again.
    private nonisolated func launchApp(at applicationURL: URL, bundleIdentifier: String, oldPID: pid_t) async throws {
        let running = NSWorkspace.shared.runningApplications.map { app in
            (pid: app.processIdentifier, bundleID: app.bundleIdentifier, isTerminated: app.isTerminated)
        }
        if SpacingRelaunch.isRelaunched(oldPID: oldPID, bundleID: bundleIdentifier, running: running) {
            logger.debug("Application \"\(bundleIdentifier, privacy: .private(mask: .hash))\" respawned on its own, so skipping launch")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = false
        try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    /// Asynchronously relaunches the given app.
    private func relaunchApp(_ app: NSRunningApplication) async throws {
        struct RelaunchError: Error { }
        guard
            let url = app.bundleURL,
            let bundleIdentifier = app.bundleIdentifier
        else {
            throw RelaunchError()
        }
        guard await quit(app) else {
            throw RelaunchError()
        }
        try await launchApp(at: url, bundleIdentifier: bundleIdentifier, oldPID: app.processIdentifier)
    }

    /// Relaunches the application with the given process identifier and returns its
    /// name if it did not quit, or `nil`.
    private func relaunchFailure(pid: pid_t) async -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        do {
            try await relaunchApp(app)
            return nil
        } catch {
            guard let name = app.localizedName else {
                return nil
            }
            if app.bundleIdentifier == "com.apple.Spotlight" {
                // Spotlight automatically relaunches, so only consider it a failure if it never quit.
                if
                    let latestSpotlightInstance = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
                    latestSpotlightInstance.processIdentifier == app.processIdentifier
                {
                    return name
                }
                return nil
            }
            return name
        }
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: Calling this restarts all apps with a menu bar item, except the system agents
    ///   that refuse to quit (Control Center, SystemUIServer, MenuBarAgent).
    func applyOffset() async throws {
        try writeSpacingPreferences()

        try? await Task.sleep(for: .milliseconds(100))

        let items: [MenuBarItem]
        if #available(macOS 27.0, *) {
            // macOS 27 has no item windows. Accessibility names the owning process of
            // every item, concealed ones included.
            items = await MenuBarItemProvider27.items()
        } else {
            items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        }

        let owners = Set(items.map { $0.sourcePID ?? $0.ownerPID }).map { pid in
            SpacingRelaunch.Owner(
                pid: pid,
                bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            )
        }
        let pids = SpacingRelaunch.processesToRelaunch(
            owners: owners,
            ownPID: ProcessInfo.processInfo.processIdentifier
        )

        var failedApps = [String]()

        // The applications relaunch at the same time, each in a task of its own on the
        // main actor; the tasks look the applications up themselves, so only process
        // identifiers cross into them.
        let relaunches = pids.compactMap { pid -> Task<String?, Never>? in
            guard NSRunningApplication(processIdentifier: pid) != nil else {
                // The process is gone, so there is nothing to relaunch.
                return nil
            }
            return Task {
                await self.relaunchFailure(pid: pid)
            }
        }
        for relaunch in relaunches {
            if let name = await relaunch.value {
                failedApps.append(name)
            }
        }

        // Control Center and SystemUIServer are not asked to quit: they refuse, so asking them
        // only made every apply wait the whole quit timeout and report them as failures
        // (see `SpacingRelaunch.processesToRelaunch`).

        if !failedApps.isEmpty {
            throw GroupedRelaunchError(failedApps: failedApps)
        }
    }
}

nonisolated private extension NSRunningApplication {
    /// A string to use for logging purposes.
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
