//
//  ApplyLedger27.swift
//  holzBar
//

import Foundation

/// Numbers the concealment applies and keeps track of who waits for them (macOS 27).
///
/// MenuBarAgent applies a concealment change some time after holzBar records it: each apply
/// queues behind the one before, and an assertion can take up to 3 s to be answered. So
/// whoever needs a change on screen, to click an item or photograph it, waits for the apply
/// that carries it. Applies finish in the order they were queued, because each waits for the
/// one before.
nonisolated struct ApplyLedger27<Waiter> {
    /// The number of the latest apply queued; 0 before the first.
    private(set) var lastQueued = 0

    /// The number of the latest apply that finished.
    private(set) var lastFinished = 0

    /// Whether the latest apply that finished succeeded; true before the first.
    private(set) var lastSucceeded = true

    /// The waiters, by a running number, with the apply each waits for.
    private var waiters = [Int: (apply: Int, waiter: Waiter)]()

    /// The running number of the latest waiter.
    private var lastWaiter = 0

    /// Whether an apply was queued that has not finished.
    var hasPending: Bool {
        lastFinished < lastQueued
    }

    /// The number the next apply queued gets.
    var nextApply: Int {
        lastQueued + 1
    }

    /// Numbers an apply that is being queued.
    mutating func queue() -> Int {
        lastQueued += 1
        return lastQueued
    }

    /// Adds a waiter for the given apply.
    ///
    /// - Returns: The waiter's number, to abandon it, or `nil` when the apply already finished
    ///   and the waiter is to be answered with ``lastSucceeded`` at once.
    mutating func wait(for apply: Int, waiter: Waiter) -> Int? {
        guard apply > lastFinished else {
            return nil
        }
        lastWaiter += 1
        waiters[lastWaiter] = (apply, waiter)
        return lastWaiter
    }

    /// Records that an apply finished.
    ///
    /// - Returns: The waiters of this apply and those before it, in the order they began
    ///   waiting; each is handed out once.
    mutating func finish(_ apply: Int, succeeded: Bool) -> [Waiter] {
        if apply >= lastFinished {
            lastSucceeded = succeeded
        }
        lastFinished = max(lastFinished, apply)
        let answered = waiters.filter { $0.value.apply <= apply }.keys.sorted()
        return answered.compactMap { waiters.removeValue(forKey: $0)?.waiter }
    }

    /// Removes a waiter that stops waiting.
    ///
    /// - Returns: The waiter, or `nil` when an apply already answered it.
    mutating func abandon(_ id: Int) -> Waiter? {
        waiters.removeValue(forKey: id)?.waiter
    }
}
