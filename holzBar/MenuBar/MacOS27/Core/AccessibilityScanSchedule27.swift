//
//  AccessibilityScanSchedule27.swift
//  holzBar
//

import Foundation

/// Decides how long to wait for each process when holzBar reads menu bar items
/// through Accessibility on macOS 27.
///
/// holzBar asks every running process for its items. Some processes never answer,
/// such as WebKit's content processes, and each costs the whole timeout on every
/// read: measured 17 of them and 8.5 s of a 10 s read. A process that times out
/// is skipped for a while, then asked again with a short timeout. A process that
/// has shown items is never skipped: a busy MenuBarAgent or item owner would
/// otherwise lose its items, and the clock its click, for a minute. Neither is a
/// young process that may own an item (``youngAge``).
nonisolated struct AccessibilityScanSchedule27 {
    static let normalTimeout: Float = 0.5
    static let retryTimeout: Float = 0.1

    /// How long after its launch a process that may own an item is never skipped.
    ///
    /// An agent busy at launch, before it reported any item, was paused at its first
    /// timeout and then for longer each time, so it could be missing from the Shelf
    /// for up to 10 minutes (D-11). While young it is asked with the normal timeout at
    /// every read. Helpers in `Frameworks` and `.xpc` services are not item owners
    /// (`AgentLaunches27.mayOwnItem`) and keep the pause, so the slow reads this
    /// schedule was built against do not come back.
    static let youngAge: TimeInterval = 30

    private static let firstPause: TimeInterval = 60
    private static let longestPause: TimeInterval = 600

    private var pauses = [pid_t: (failures: Int, retryAt: TimeInterval)]()
    private var itemOwners = Set<pid_t>()

    /// How many timeouts of young processes were not paused. For diagnostics.
    private(set) var youngRetries = 0

    /// The timeout to ask the process with, or `nil` to skip it for now.
    func timeout(for pid: pid_t, now: TimeInterval) -> Float? {
        guard let pause = pauses[pid] else {
            return Self.normalTimeout
        }
        return now >= pause.retryAt ? Self.retryTimeout : nil
    }

    /// Remembers a process that published menu bar items.
    mutating func recordItems(pid: pid_t) {
        itemOwners.insert(pid)
        pauses[pid] = nil
    }

    /// Records how a process answered a read.
    ///
    /// - Parameters:
    ///   - pid: The process.
    ///   - timedOut: Whether it missed the timeout.
    ///   - now: When it was asked.
    ///   - isYoung: Whether it launched less than ``youngAge`` ago and may own an item; such
    ///     a process is not paused for a timeout.
    mutating func record(pid: pid_t, timedOut: Bool, now: TimeInterval, isYoung: Bool = false) {
        guard timedOut, !itemOwners.contains(pid) else {
            pauses[pid] = nil
            return
        }
        if isYoung {
            youngRetries += 1
            pauses[pid] = nil
            return
        }
        let failures = (pauses[pid]?.failures ?? 0) + 1
        let pause = min(Self.firstPause * pow(2, Double(failures - 1)), Self.longestPause)
        pauses[pid] = (failures, now + pause)
    }

    /// Forgets processes that are no longer running.
    mutating func retain(running pids: Set<pid_t>) {
        pauses = pauses.filter { pids.contains($0.key) }
        itemOwners.formIntersection(pids)
    }
}
