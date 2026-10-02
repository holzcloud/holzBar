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
}
