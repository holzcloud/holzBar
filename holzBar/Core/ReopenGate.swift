//
//  ReopenGate.swift
//  holzBar
//

import Foundation

/// Decides whether a reopen of the running app opens Settings.
///
/// A reopen is an Apple event the system sends to a running app when the user starts it
/// again: a click on its Dock icon, a double-click in the Finder, Spotlight, Launchpad.
/// holzBar answers it by opening Settings. On macOS 27 the machinery behind Siri and
/// Shortcuts sends the same event whenever anything happens, so Settings would open by
/// itself. So the sender decides: only the Apple launchers of ``userLaunchSenders`` open
/// Settings, every other sender does nothing, and a second reopen within ``rateLimit`` of
/// the last one that opened Settings does nothing either.
///
/// A reopen without a readable sender is ignored on purpose: holzBar's menu still opens
/// Settings, so nothing is lost, while a guess would let the unwanted reopens through.
///
/// The type holds no state and reads no clock: the caller passes the time and remembers
/// when Settings was last opened, and moves that time only on ``Decision/openSettings``.
nonisolated enum ReopenGate {
    /// Who sent a reopen, as bundle identifiers. Nothing else is kept.
    nonisolated struct Sender: Equatable, Sendable {
        /// The app that sent the event, or `nil` when it cannot be told.
        var bundleID: String?

        /// The app the event came from originally, when the system relayed it, or `nil`.
        var originalBundleID: String?
    }

    /// Why a reopen does nothing.
    nonisolated enum Reason: String, Equatable, Sendable {
        /// The last reopen that opened Settings was less than ``ReopenGate/rateLimit`` ago.
        case rateLimited
        /// The sender is not one of the launchers, or is marked as never to be one.
        case notUserLaunch
        /// Neither the sender nor the original sender could be told.
        case unknownSender
    }

    /// What a reopen does.
    nonisolated enum Decision: Equatable, Sendable {
        /// Open Settings.
        case openSettings
        /// Do nothing, for the given reason.
        case ignore(Reason)
    }

    /// The launchers whose reopen opens Settings: the Dock, the Finder, Spotlight and
    /// Launchpad. Strict on purpose; it is fitted to what a real Mac measures.
    static let userLaunchSenders: Set<String> = [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.Spotlight",
        "com.apple.launchpad.launcher",
    ]

    /// Lower-case words that mark a sender as the Siri or Shortcuts machinery. A sender
    /// whose identifier contains one never opens Settings, even when its original sender
    /// is a launcher. The words follow MonitorControl 4.4.0's fix of the same problem.
    static let neverMarkers = ["siri", "shortcut", "workflow"]

    /// The shortest time between two reopens that open Settings.
    static let rateLimit = Duration.seconds(2)

    /// Whether the sender is a launcher of ``userLaunchSenders`` and none of its identifiers
    /// carries a never-marker. Identifiers compare without regard to case.
    static func isUserLaunch(_ sender: Sender) -> Bool {
        let identifiers = [sender.bundleID, sender.originalBundleID].compactMap { $0?.lowercased() }
        if identifiers.contains(where: { identifier in neverMarkers.contains { identifier.contains($0) } }) {
            return false
        }
        let allowed = Set(userLaunchSenders.map { $0.lowercased() })
        return identifiers.contains { allowed.contains($0) }
    }

    /// What a reopen from the sender does.
    ///
    /// - Parameters:
    ///   - sender: Who sent the reopen.
    ///   - now: The current time.
    ///   - lastOpened: When a reopen last opened Settings, or `nil` when none did.
    static func decide(
        sender: Sender,
        now: ContinuousClock.Instant,
        lastOpened: ContinuousClock.Instant?
    ) -> Decision {
        if sender.bundleID == nil, sender.originalBundleID == nil {
            return .ignore(.unknownSender)
        }
        guard isUserLaunch(sender) else {
            return .ignore(.notUserLaunch)
        }
        if let lastOpened, lastOpened.duration(to: now) < rateLimit {
            return .ignore(.rateLimited)
        }
        return .openSettings
    }
}
