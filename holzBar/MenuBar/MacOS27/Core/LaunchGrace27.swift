//
//  LaunchGrace27.swift
//  holzBar
//

import Foundation

/// Applications that launched while their section is concealed, allowed on the bar until
/// their item exists (macOS 27).
///
/// Concealing an application before its status item exists makes MenuBarAgent give the item
/// 3 points, and it stays squashed when it is revealed (jordanbaird/Ice#1007). So a launching
/// application whose section is concealed is shown until its item appears in a read of the
/// bar, or for at most ``timeout``, and then concealed. Each grace is ended exactly once, so
/// the caller can balance its allowance.
nonisolated struct LaunchGrace27 {
    /// How long a launching application is allowed at most.
    static let timeout = Duration.seconds(10)

    /// The applications allowed now, with when their grace began.
    private var started = [String: ContinuousClock.Instant]()

    /// The applications allowed now.
    var allowed: Set<String> {
        Set(started.keys)
    }

    /// Starts a grace for an application that launched.
    ///
    /// - Parameters:
    ///   - bundleID: The application's bundle identifier.
    ///   - isConcealed: Whether its saved section is concealed now; a visible application
    ///     needs no grace.
    ///   - now: When it launched.
    /// - Returns: Whether a grace began (not when the app is visible or already allowed).
    @discardableResult
    mutating func begin(_ bundleID: String, isConcealed: Bool, at now: ContinuousClock.Instant) -> Bool {
        guard isConcealed, started[bundleID] == nil else {
            return false
        }
        started[bundleID] = now
        return true
    }

    /// Ends the graces of the applications whose items appeared.
    ///
    /// - Returns: The applications whose grace ended.
    mutating func itemsAppeared(_ bundleIDs: Set<String>) -> [String] {
        let ended = started.keys.filter(bundleIDs.contains).sorted()
        for bundleID in ended {
            started[bundleID] = nil
        }
        return ended
    }

    /// Ends the graces that lasted ``timeout`` without an item.
    ///
    /// - Returns: The applications whose grace ended.
    mutating func expired(at now: ContinuousClock.Instant) -> [String] {
        let ended = started
            .filter { $0.value.duration(to: now) >= Self.timeout }
            .map(\.key)
            .sorted()
        for bundleID in ended {
            started[bundleID] = nil
        }
        return ended
    }
}
