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

    /// Asynchronously launches the app at the given URL.
    private nonisolated func launchApp(at applicationURL: URL, bundleIdentifier: String) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            logger.debug("Application \"\(app.logString, privacy: .private(mask: .hash))\" is already open, so skipping launch")
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
        try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: Calling this restarts all apps with a menu bar item.
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

        await withTaskGroup(of: String?.self) { group in
            for pid in pids {
                guard let app = NSRunningApplication(processIdentifier: pid) else {
                    // The process is gone, so there is nothing to relaunch.
                    continue
                }
                group.addTask { @MainActor in
                    do {
                        try await self.relaunchApp(app)
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
            }
            for await name in group {
                if let name {
                    failedApps.append(name)
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(100))

        // Control Center relaunches itself once told to quit.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: SpacingRelaunch.controlCenterBundleIdentifier).first {
            let didQuit = await quit(app)
            if !didQuit, let name = app.localizedName {
                failedApps.append(name)
            }
        }

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
