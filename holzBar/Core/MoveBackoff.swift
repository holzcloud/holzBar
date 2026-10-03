//
//  MoveBackoff.swift
//  holzBar
//

import Foundation

/// Pauses holzBar's automatic item moves when they run away.
///
/// holzBar moves items on its own: new items into their section, Live Activities into
/// view, temporarily shown items back, the dividers into order, a profile's layout. When
/// macOS keeps putting an item back, the same item is dragged again and again; when the
/// bar refuses moves, every failed one holds the hidden pointer for its whole budget. So
/// both are counted in a sliding window (``window``), and past a limit automatic moves
/// are refused for a pause that doubles with each trip (``initialPause`` up to
/// ``maximumPause``) and starts over when ``resetInterval`` passed after the last pause
/// without a trip.
///
/// Moves the user makes are never counted and are always allowed; one ends a pause.
///
/// Adapted from Thaw's `MoveCircuitBreaker` (GPL-3.0, see NOTICE). Every method takes the
/// current time, so the type can be tested without a clock.
nonisolated struct MoveBackoff {
    /// How far back the counts look.
    static let window = Duration.seconds(60)

    /// Automatic moves of one item allowed in the window; one more trips the back-off.
    static let sameItemLimit = 4

    /// Failed automatic moves in the window that trip the back-off.
    static let failureLimit = 8

    /// The first pause after a trip.
    static let initialPause = Duration.seconds(60)

    /// The longest pause.
    static let maximumPause = Duration.seconds(600)

    /// How long after the last pause ended without a trip before the pause starts over at
    /// ``initialPause``.
    static let resetInterval = Duration.seconds(300)

    /// What is counted.
    private nonisolated enum Signal: Equatable {
        case move(identifier: String)
        case failure
    }

    /// A counted signal and when it happened.
    private nonisolated struct Record {
        let at: ContinuousClock.Instant
        let signal: Signal
    }

    /// The signals in the window.
    private var records = [Record]()

    /// When the current pause ends, or `nil` when automatic moves are not paused.
    private(set) var pausedUntil: ContinuousClock.Instant?

    /// When the last pause ended (or was to end, if a user move ended it early).
    private var lastPauseEnd: ContinuousClock.Instant?

    /// The pause the next trip starts.
    private(set) var nextPause = MoveBackoff.initialPause

    /// Whether an automatic move may run at the given time.
    func allowsAutomaticMove(at now: ContinuousClock.Instant) -> Bool {
        guard let pausedUntil else {
            return true
        }
        return now >= pausedUntil
    }

    /// Counts an automatic move of the item with the given identifier.
    ///
    /// - Returns: `true` when this move tripped the back-off; the move should then not run.
    @discardableResult
    mutating func recordAutomaticMove(identifier: String, at now: ContinuousClock.Instant) -> Bool {
        record(.move(identifier: identifier), at: now)
        let moves = records.count { $0.signal == .move(identifier: identifier) }
        guard moves > Self.sameItemLimit else {
            return false
        }
        trip(at: now)
        return true
    }

    /// Counts a failed automatic move.
    ///
    /// - Returns: `true` when this failure tripped the back-off.
    @discardableResult
    mutating func recordFailure(at now: ContinuousClock.Instant) -> Bool {
        record(.failure, at: now)
        let failures = records.count { $0.signal == .failure }
        guard failures >= Self.failureLimit else {
            return false
        }
        trip(at: now)
        return true
    }

    /// Notes a move the user made: it ends a pause and clears the counts. The grown pause is
    /// kept for the next trip.
    mutating func recordUserMove() {
        records.removeAll()
        pausedUntil = nil
    }

    /// Adds a signal and drops the ones that left the window.
    private mutating func record(_ signal: Signal, at now: ContinuousClock.Instant) {
        records.removeAll { $0.at.duration(to: now) > Self.window }
        records.append(Record(at: now, signal: signal))
    }

    /// Pauses automatic moves and doubles the next pause.
    private mutating func trip(at now: ContinuousClock.Instant) {
        // A trip long after the last pause means the bar had settled in between, so the
        // pause starts over rather than punishing a one-off. Measured from the end of the
        // pause, as no trip can happen during one.
        if let lastPauseEnd, lastPauseEnd.duration(to: now) >= Self.resetInterval {
            nextPause = Self.initialPause
        }
        let pauseEnd = now + nextPause
        lastPauseEnd = pauseEnd
        pausedUntil = pauseEnd
        nextPause = min(nextPause * 2, Self.maximumPause)
        // The pause stands for what was counted; afterwards the counts start over.
        records.removeAll()
    }
}
