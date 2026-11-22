//
//  AgentRestartBreaker.swift
//  holzBar
//

import Foundation

/// Bounds how often holzBar applies the concealment again after MenuBarAgent restarted.
///
/// holzBar applies the hiding again after every MenuBarAgent restart (1.0.5). A restart that
/// holzBar's own assertion causes would make that a loop: restart, apply, restart. So the
/// restarts are counted in a sliding window (``window``), and past ``restartLimit`` the breaker
/// trips for ``trippedFor``: holzBar stops hiding and shows every item, because a bar that
/// shows everything beats a bar that locks up (the Core Value). The thresholds are holzBar's own
/// choice.
///
/// A restart holzBar asks for itself (a "Restart menu bar" command) is announced with
/// ``expectRestart(at:)`` and not counted. Every method takes the current time, so the type can
/// be tested without a clock; the shape follows ``MoveBackoff`` (ideas only, no Thaw code is
/// copied).
nonisolated struct AgentRestartBreaker: Equatable, Sendable {
    /// How far back the restarts count.
    static let window = Duration.seconds(600)

    /// Restarts allowed in the window; one more trips the breaker.
    static let restartLimit = 3

    /// How long a trip lasts.
    static let trippedFor = Duration.seconds(1800)

    /// How long after ``expectRestart(at:)`` a restart still counts as the expected one.
    static let expectedWithin = Duration.seconds(10)

    /// Expectations closer together than this count as one (a double click).
    static let manualGap = Duration.seconds(5)

    /// What a restart means.
    nonisolated enum Outcome: Equatable, Sendable {
        /// An unexpected restart within the limit: apply the concealment again.
        case reapply
        /// A restart holzBar asked for: apply again, not counted.
        case expected
        /// The breaker is tripped: hiding stops until it ends.
        case tripped
    }

    /// The unexpected restarts in the window.
    private var restarts = [ContinuousClock.Instant]()

    /// When the trip ends, or `nil` when the breaker is not tripped.
    private(set) var trippedUntil: ContinuousClock.Instant?

    /// When holzBar last asked for a restart that is not yet answered.
    private var expectedAt: ContinuousClock.Instant?

    /// When the last accepted expectation was made.
    private var lastExpectation: ContinuousClock.Instant?

    /// What the last accepted expectation replaced, to take it back with
    /// ``cancelExpectation()``.
    private var beforeExpectation: Before?

    private struct Before: Equatable, Sendable {
        var expectedAt: ContinuousClock.Instant?
        var lastExpectation: ContinuousClock.Instant?
    }

    /// Whether hiding is stopped at the given time.
    func isTripped(at now: ContinuousClock.Instant) -> Bool {
        guard let trippedUntil else {
            return false
        }
        return now < trippedUntil
    }

    /// Counts a restart of MenuBarAgent and says what to do about it.
    @discardableResult
    mutating func record(at now: ContinuousClock.Instant) -> Outcome {
        beforeExpectation = nil
        if isTripped(at: now) {
            return .tripped
        }
        trippedUntil = nil
        if let expectedAt {
            self.expectedAt = nil
            if expectedAt <= now, expectedAt.duration(to: now) <= Self.expectedWithin {
                return .expected
            }
        }
        restarts.removeAll { $0.duration(to: now) > Self.window }
        restarts.append(now)
        guard restarts.count > Self.restartLimit else {
            return .reapply
        }
        trippedUntil = now + Self.trippedFor
        restarts.removeAll()
        return .tripped
    }

    /// Announces a restart holzBar is about to cause, so the next one is not counted.
    ///
    /// - Returns: `false` when the last expectation was less than ``manualGap`` ago and this one
    ///   is ignored.
    @discardableResult
    mutating func expectRestart(at now: ContinuousClock.Instant) -> Bool {
        if let lastExpectation, lastExpectation <= now, lastExpectation.duration(to: now) < Self.manualGap {
            return false
        }
        beforeExpectation = Before(expectedAt: expectedAt, lastExpectation: lastExpectation)
        lastExpectation = now
        expectedAt = now
        return true
    }

    /// Takes back the last accepted expectation, when the restart it announced was never asked
    /// for: the next restart counts again and the manual gap does not apply to a retry.
    mutating func cancelExpectation() {
        guard let beforeExpectation else {
            return
        }
        expectedAt = beforeExpectation.expectedAt
        lastExpectation = beforeExpectation.lastExpectation
        self.beforeExpectation = nil
    }

    /// Ends a trip and clears the counts, as a user action wants hiding back. A pending
    /// expectation and the manual gap stay.
    mutating func reset() {
        restarts.removeAll()
        trippedUntil = nil
    }
}
