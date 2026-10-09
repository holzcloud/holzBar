//
//  SpacingRelaunch.swift
//  holzBar
//

import Foundation

/// The pure decisions of the menu bar item spacing relaunch.
///
/// Applying a spacing offset only takes effect in apps that are started again, so holzBar
/// quits and reopens every process that owns a menu bar item. This type decides which of
/// those processes are relaunched; `MenuBarItemSpacingManager` does the quitting and
/// launching.
nonisolated enum SpacingRelaunch {
    /// A process that owns at least one menu bar item.
    nonisolated struct Owner: Hashable {
        /// The process identifier of the owner.
        let pid: pid_t
        /// The bundle identifier of the owner, if it has one.
        let bundleIdentifier: String?
    }

    /// The bundle identifier of Control Center.
    ///
    /// Control Center refuses to quit: it answers a quit request with `NSTerminateCancel`
    /// (measured on macOS 26.7.1). Asking it only cost the whole ``quitTimeout`` and reported
    /// it as a failure on every apply, so holzBar does not ask it; its items take the new
    /// spacing at the next login.
    static let controlCenterBundleIdentifier = "com.apple.controlcenter"

    /// The bundle identifier of SystemUIServer.
    ///
    /// SystemUIServer ignores a quit request (measured on macOS 26.7.1), so, like Control
    /// Center, it is not asked; its items take the new spacing at the next login.
    static let systemUIServerBundleIdentifier = "com.apple.systemuiserver"

    /// The bundle identifier of MenuBarAgent.
    ///
    /// On macOS 27 MenuBarAgent hosts the system items (the same identifier as
    /// `MenuBarItemProvider27.menuBarAgentBundleID`). It is a system agent, never quit and
    /// reopened by holzBar.
    static let menuBarAgentBundleIdentifier = "com.apple.MenuBarAgent"

    /// The processes to quit and reopen, sorted by process identifier.
    ///
    /// Every distinct process of `owners` is returned except holzBar itself (`ownPID`),
    /// Control Center, SystemUIServer and MenuBarAgent. A skipped owner never stops the
    /// others from being relaunched.
    ///
    /// - Parameters:
    ///   - owners: The processes that own the menu bar items.
    ///   - ownPID: The process identifier of holzBar.
    static func processesToRelaunch(owners: [Owner], ownPID: pid_t) -> [pid_t] {
        let skippedBundleIdentifiers: Set<String> = [
            controlCenterBundleIdentifier,
            systemUIServerBundleIdentifier,
            menuBarAgentBundleIdentifier,
        ]
        let pids = owners.compactMap { owner -> pid_t? in
            guard owner.pid != ownPID else {
                return nil
            }
            if let bundleIdentifier = owner.bundleIdentifier, skippedBundleIdentifiers.contains(bundleIdentifier) {
                return nil
            }
            return owner.pid
        }
        return Set(pids).sorted()
    }

    /// The global preferences that set the menu bar item spacing, in the order they are written.
    ///
    /// `NSStatusItemSpacing` is the space between items and `NSStatusItemSelectionPadding`
    /// the padding of an item's highlight. Both live in the current host's global domain.
    static let spacingPreferenceKeys = [
        "NSStatusItemSpacing",
        "NSStatusItemSelectionPadding",
    ]

    /// macOS's default for both spacing preferences, in points.
    static let defaultSpacing = 16

    /// The value to write for each spacing preference.
    ///
    /// - Parameter offset: The offset the user chose, in points.
    /// - Returns: `nil` for an offset of 0, which restores macOS's default by removing the
    ///   preferences, otherwise ``defaultSpacing`` plus `offset`.
    static func spacingPreferenceValue(forOffset offset: Int) -> Int? {
        guard offset != 0 else {
            return nil
        }
        return defaultSpacing + offset
    }

    /// A running process, as `NSWorkspace` lists it.
    typealias RunningProcess = (pid: pid_t, bundleID: String?, isTerminated: Bool)

    /// Whether the app that was quit is running again on its own, so it must not be launched
    /// a second time.
    ///
    /// An app that respawns (a helper relaunched by launchd, an app that restarts itself)
    /// runs under a new process. The old process can still be listed while it quits; it
    /// does not count, so the app is launched when nothing else runs (jordanbaird/Ice#923).
    ///
    /// - Parameters:
    ///   - oldPID: The process that was quit.
    ///   - bundleID: The app's bundle identifier.
    ///   - running: The running processes.
    static func isRelaunched(oldPID: pid_t, bundleID: String, running: [RunningProcess]) -> Bool {
        running.contains { process in
            process.pid != oldPID && process.bundleID == bundleID && !process.isTerminated
        }
    }

    /// Applies a spacing, ends its progress and only then reports a failure.
    ///
    /// The progress (the spinner next to Apply) ends as soon as `apply` returns or throws. The
    /// report is an alert that waits for the user, and by then holzBar is often not the active
    /// app, so its sheet can sit beneath the active app's windows where nobody sees it. Ending
    /// the progress after the report kept the spinner going until that hidden alert was found
    /// and dismissed (measured on macOS 26.7.1).
    ///
    /// - Parameters:
    ///   - apply: Applies the spacing.
    ///   - finished: Ends the progress; called once, whether `apply` succeeded or not.
    ///   - reportFailure: Reports the error `apply` threw; not called when it succeeded.
    static func apply(
        _ apply: () async throws -> Void,
        finished: () -> Void,
        reportFailure: (any Error) async -> Void
    ) async {
        do {
            try await apply()
        } catch {
            finished()
            await reportFailure(error)
            return
        }
        finished()
    }

    /// How long an app gets to quit after being asked.
    ///
    /// Long enough for an app that saves or uploads on quit. An app that is still running
    /// then is left alone and reported.
    static let quitTimeout: Duration = .seconds(10)

    /// Waits for `event` for at most `timeout`.
    ///
    /// Runs `event` and a sleep of `timeout` side by side, takes whichever finishes first and
    /// cancels the other. It always returns: with no continuation to leak and nothing polled.
    /// `event` must return when its task is cancelled (iterating an `AsyncStream` does),
    /// because the wait finishes only once both of them have.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait for the event.
    ///   - event: Returns once the event has happened.
    /// - Returns: `true` as soon as the event happens, `false` once the timeout has passed
    ///   and `false` at once when the waiting task is cancelled.
    static func waitUntil(timeout: Duration, _ event: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await event()
                return !Task.isCancelled
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let happened = await group.next() ?? false
            group.cancelAll()
            return happened
        }
    }
}
