//
//  SourcePIDLookupSchedule.swift
//  holzBar
//

import Foundation

/// Bounds the Accessibility scans that find the app behind a menu bar item on macOS 26.
///
/// On macOS 26 Control Center owns every item window, so holzBar asks every app with an
/// extras menu bar which of its items sits where the window is. One app that answers
/// slowly must not hold up every item read: every call waits ``messagingTimeout`` at most,
/// one lookup stops asking after ``lookupBudget``, at most ``maximumChildren`` items are
/// read from one app, and an app that ran into the timeout is not asked again for a pause
/// that doubles from ``firstPause`` up to ``longestPause``.
///
/// holzBar's own process is never paused: it answers on the main thread, which a lookup
/// never blocks, and pausing it would leave its group and spacer items without their app.
///
/// Every method takes the current time, so the type can be tested without a clock.
nonisolated struct SourcePIDLookupSchedule {
    /// How long one Accessibility call to an app waits for its answer, in seconds.
    static let messagingTimeout: Float = 0.5

    /// How long a call took when it ran into ``messagingTimeout``.
    ///
    /// Only a call that waited for the timeout takes this long. A failed call can also
    /// come back at once, with the same error as a timeout, which is why the time is
    /// measured instead.
    static let timeoutThreshold = Duration.milliseconds(450)

    /// The most time one lookup spends asking apps, checked between calls.
    static let lookupBudget = Duration.seconds(2)

    /// The most extras menu bar children read from one app.
    ///
    /// Well above Control Center's roughly twenty items, and it bounds an app that
    /// reports thousands.
    static let maximumChildren = 64

    /// The first pause of an app that ran into the timeout.
    static let firstPause = Duration.seconds(10)

    /// The longest pause.
    static let longestPause = Duration.seconds(60)

    /// How long a window that a finished scan did not find is not scanned again.
    static let failedLookupInterval = Duration.seconds(30)

    /// A paused app: how long its pause is, and when it may be asked again.
    private nonisolated struct Pause {
        let length: Duration
        let until: ContinuousClock.Instant
    }

    /// holzBar's own process.
    private let ownPID: pid_t

    /// The paused apps, by process.
    private var pauses = [pid_t: Pause]()

    /// Creates a schedule in which no app is paused.
    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    /// Whether the app with the given process may be asked at the given time.
    func mayAsk(_ pid: pid_t, at now: ContinuousClock.Instant) -> Bool {
        guard let pause = pauses[pid] else {
            return true
        }
        return now >= pause.until
    }

    /// Records whether the app with the given process ran into the timeout.
    ///
    /// An answer in time ends the app's pause, and the next timeout pauses it for
    /// ``firstPause`` again.
    mutating func record(_ pid: pid_t, timedOut: Bool, at now: ContinuousClock.Instant) {
        guard timedOut, pid != ownPID else {
            pauses[pid] = nil
            return
        }
        let length = pauses[pid].map { min($0.length * 2, Self.longestPause) } ?? Self.firstPause
        pauses[pid] = Pause(length: length, until: now + length)
    }

    /// Forgets the processes that are no longer running.
    mutating func retain(running pids: Set<pid_t>) {
        pauses = pauses.filter { pids.contains($0.key) }
    }

    /// Whether a call that took the given time ran into the messaging timeout.
    static func didTimeOut(after elapsed: Duration) -> Bool {
        elapsed >= timeoutThreshold
    }

    /// Whether a lookup that started at the given time has used up its budget.
    static func isOverBudget(startedAt start: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Bool {
        start.duration(to: now) >= lookupBudget
    }

    /// Whether a window that a finished scan did not find is scanned again: after
    /// ``failedLookupInterval``, or as soon as an app the scan skipped can be asked.
    static func shouldRescan(failedAt: ContinuousClock.Instant, now: ContinuousClock.Instant, skippedAppIsReady: Bool) -> Bool {
        skippedAppIsReady || failedAt.duration(to: now) >= failedLookupInterval
    }
}
