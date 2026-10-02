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
enum SpacingRelaunch {
    /// A process that owns at least one menu bar item.
    struct Owner: Hashable {
        /// The process identifier of the owner.
        let pid: pid_t
        /// The bundle identifier of the owner, if it has one.
        let bundleIdentifier: String?
    }

    /// The bundle identifier of Control Center.
    ///
    /// Control Center relaunches itself once told to quit, so the manager asks it once,
    /// after the other apps.
    static let controlCenterBundleIdentifier = "com.apple.controlcenter"

    /// The bundle identifier of MenuBarAgent.
    ///
    /// On macOS 27 MenuBarAgent hosts the system items (the same identifier as
    /// `MenuBarItemProvider27.menuBarAgentBundleID`). It is a system agent, never quit and
    /// reopened by holzBar.
    static let menuBarAgentBundleIdentifier = "com.apple.MenuBarAgent"

    /// The processes to quit and reopen, sorted by process identifier.
    ///
    /// Every distinct process of `owners` is returned except holzBar itself (`ownPID`),
    /// Control Center and MenuBarAgent. A skipped owner never stops the others from being
    /// relaunched.
    ///
    /// - Parameters:
    ///   - owners: The processes that own the menu bar items.
    ///   - ownPID: The process identifier of holzBar.
    static func processesToRelaunch(owners: [Owner], ownPID: pid_t) -> [pid_t] {
        let skippedBundleIdentifiers: Set<String> = [
            controlCenterBundleIdentifier,
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

    /// How long an app gets to quit after being asked.
    ///
    /// Long enough for an app that saves or syncs on quit. An app that is still running
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
