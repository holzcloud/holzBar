//
//  ObserverRegistrationSchedule27.swift
//  holzBar
//

import Foundation

/// Decides when holzBar tries again to register its Accessibility observer for a process
/// that owns menu bar items on macOS 27 (`ItemChangeObserver27`).
///
/// The owners are handed over on every item-cache refresh, and an owner whose registration
/// failed was asked again on each of them: a busy process, often one that just launched,
/// cost the whole wait every time. A registration that timed out is tried again at the
/// first refresh at least ``firstPause`` later, a pause that doubles up to
/// ``longestPause``. A process that does not support the notifications is not asked again
/// while it runs; a relaunch gets a new process identifier. Retries ride on the refreshes,
/// so there is no timer.
///
/// Times are seconds of a monotonic clock, passed in, so the rules can be tested.
nonisolated struct ObserverRegistrationSchedule27 {
    /// How a registration ended.
    enum Outcome {
        /// At least one notification was added.
        case registered
        /// The process did not answer in time, or the registration failed otherwise.
        case timedOut
        /// The process does not post the notifications.
        case unsupported
    }

    /// The first pause after a registration timed out.
    static let firstPause: TimeInterval = 5

    /// The longest pause.
    static let longestPause: TimeInterval = 60

    /// Why a process is not asked now.
    private enum Pause {
        case timedOut(failures: Int, retryAt: TimeInterval)
        case unsupported
    }

    /// The paused processes.
    private var pauses = [pid_t: Pause]()

    /// Whether no process is paused.
    var isEmpty: Bool { pauses.isEmpty }

    /// Whether the process may be asked now.
    func allowsRegistration(of pid: pid_t, now: TimeInterval) -> Bool {
        switch pauses[pid] {
        case nil:
            true
        case let .timedOut(_, retryAt):
            now >= retryAt
        case .unsupported:
            false
        }
    }

    /// Records how a registration of the process ended.
    mutating func record(_ outcome: Outcome, for pid: pid_t, now: TimeInterval) {
        switch outcome {
        case .registered:
            pauses[pid] = nil
        case .unsupported:
            pauses[pid] = .unsupported
        case .timedOut:
            var failures = 1
            if case let .timedOut(previous, _) = pauses[pid] {
                failures = previous + 1
            }
            let pause = min(Self.firstPause * pow(2, Double(failures - 1)), Self.longestPause)
            pauses[pid] = .timedOut(failures: failures, retryAt: now + pause)
        }
    }

    /// Forgets processes that are no longer running.
    mutating func retain(running pids: Set<pid_t>) {
        pauses = pauses.filter { pids.contains($0.key) }
    }
}
