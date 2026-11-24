//
//  OverflowAutoMove.swift
//  holzBar
//

import Foundation

/// The gate of Automatic, the third choice of "When the menu bar is full" (Phase 97, COMF-02,
/// D-02, D-09, D-10): it decides when holzBar may move apps to Hidden by itself.
///
/// Automatic changes the user's saved layout without a click, so it acts only on what macOS
/// already did, and only when nothing argues against it:
///
/// - **Two reads.** One folded reading is a first read; a second folded reading at least
///   ``Policy/readGap`` later with nothing in between that said otherwise gives the pass. A
///   clear or unknown reading, or any closed condition, throws the first read away.
/// - **Never on a guess.** An unknown reading never gives a pass; the caller reports a
///   prediction alone as unknown.
/// - **Quiet start.** Nothing happens in the first ``Policy/quietStart`` after holzBar starts or
///   after the system has settled following a wake or a display change.
/// - **One pass per episode.** After a pass no further pass runs until the bar has shown no
///   overflow for ``Policy/episodeEnd``, so a move can never trigger another move (D-09
///   hysteresis). A fold within that time keeps the episode. Readings within
///   ``Policy/afterPass`` after a pass wait for the end of that time.
/// - **Breaker.** ``Policy/breakerLimit`` passes within ``Policy/breakerWindow`` pause the gate
///   until the oldest of them leaves the window.
///
/// Every method takes the current time and nothing reads a clock, so the type is tested
/// without one. The numbers are assumed values (research A2 and A9) that the tests pin; a
/// probe on a Mac may change them.
nonisolated struct OverflowAutoMove: Equatable, Sendable {
    /// What the bar looks like in one reading.
    nonisolated enum Reading: Equatable, Sendable {
        /// macOS folded Visible apps away.
        case folded
        /// The bar is not full.
        case clear
        /// The state cannot be told, or only a prediction says the bar is full.
        case unknown
    }

    /// What holds Automatic back besides the reading.
    nonisolated struct Conditions: Equatable, Sendable {
        /// The system has settled: not locked, asleep or still settling after a wake.
        var isSettled: Bool
        /// A menu bar item is being dragged.
        var isDragging: Bool
        /// An application is in its launch grace.
        var inLaunchGrace: Bool
        /// Layout is open.
        var isLayoutOpen: Bool
        /// A pass would move at least one app.
        var hasCandidates: Bool
    }

    /// What the caller does next.
    nonisolated enum Decision: Equatable, Sendable {
        /// Nothing now; the next change of the observed state asks again.
        case nothing
        /// Ask again at this instant: the only wait the caller arms.
        case check(at: ContinuousClock.Instant)
        /// Move the planner's apps now and report it through ``didRunPass(at:)``.
        case runPass
    }

    /// Every number of the gate.
    nonisolated enum Policy {
        /// The least time between the first and the second folded reading. [ASSUMED] A2.
        static let readGap = Duration.seconds(5)
        /// How long the bar must show no overflow before another pass may run. [ASSUMED] A2.
        static let episodeEnd = Duration.seconds(30)
        /// The quiet time after holzBar starts or the system settles. [ASSUMED] A9.
        static let quietStart = Duration.seconds(60)
        /// The window in which the passes are counted. [ASSUMED] A2.
        static let breakerWindow = Duration.seconds(600)
        /// The passes in the window that pause the gate. [ASSUMED] A2.
        static let breakerLimit = 3
        /// How long readings wait after a pass. [ASSUMED] A2.
        static let afterPass = Duration.seconds(2)
    }

    /// When the quiet start began: holzBar's start or the last settle.
    private var quietFrom: ContinuousClock.Instant

    /// When the first folded reading of the pending confirmation was taken.
    private var firstFoldedAt: ContinuousClock.Instant?

    /// When the last pass ran.
    private var lastPassAt: ContinuousClock.Instant?

    /// Whether a pass ran in the current episode and the episode has not ended.
    private var isInEpisode = false

    /// When the bar began to show no overflow, while a clear streak runs in an episode.
    private var clearSince: ContinuousClock.Instant?

    /// The passes in the window, oldest first.
    private var passes = [ContinuousClock.Instant]()

    init(startedAt: ContinuousClock.Instant) {
        quietFrom = startedAt
    }

    /// Takes one reading and says what to do.
    ///
    /// - Parameters:
    ///   - reading: What the bar looks like now.
    ///   - conditions: What else holds Automatic back.
    ///   - now: The current time.
    mutating func note(_ reading: Reading, conditions: Conditions, at now: ContinuousClock.Instant) -> Decision {
        if let lastPassAt {
            let end = lastPassAt + Policy.afterPass
            if now < end {
                return .check(at: end)
            }
        }
        switch reading {
        case .unknown:
            firstFoldedAt = nil
            clearSince = nil
            return .nothing
        case .clear:
            firstFoldedAt = nil
            if isInEpisode {
                if let clearSince {
                    if clearSince.duration(to: now) >= Policy.episodeEnd {
                        endEpisode()
                    }
                } else {
                    clearSince = now
                }
            }
            return .nothing
        case .folded:
            return noteFolded(conditions: conditions, at: now)
        }
    }

    /// A folded reading: the episode, the quiet start, the breaker, the conditions, then the two reads.
    private mutating func noteFolded(conditions: Conditions, at now: ContinuousClock.Instant) -> Decision {
        if isInEpisode {
            if let clearSince, clearSince.duration(to: now) >= Policy.episodeEnd {
                endEpisode()
            } else {
                // A fold within the time keeps the episode; the clear streak starts over.
                clearSince = nil
                firstFoldedAt = nil
                return .nothing
            }
        }
        let quietEnd = quietFrom + Policy.quietStart
        if now < quietEnd {
            firstFoldedAt = nil
            return .check(at: quietEnd)
        }
        if let until = pausedUntil(at: now) {
            firstFoldedAt = nil
            return .check(at: until)
        }
        guard
            conditions.isSettled,
            !conditions.isDragging,
            !conditions.inLaunchGrace,
            !conditions.isLayoutOpen,
            conditions.hasCandidates
        else {
            firstFoldedAt = nil
            return .nothing
        }
        guard let first = firstFoldedAt else {
            firstFoldedAt = now
            return .check(at: now + Policy.readGap)
        }
        let due = first + Policy.readGap
        guard now >= due else {
            return .check(at: due)
        }
        return .runPass
    }

    /// The pass ran: it is counted, the episode begins and the confirmation starts over.
    mutating func didRunPass(at now: ContinuousClock.Instant) {
        passes.removeAll { $0.duration(to: now) >= Policy.breakerWindow }
        passes.append(now)
        lastPassAt = now
        isInEpisode = true
        clearSince = nil
        firstFoldedAt = nil
    }

    /// The pass the gate asked for did not run (the caller's fresh read no longer said folded,
    /// or a pass was already running): the pending confirmation starts over.
    mutating func didNotRunPass() {
        firstFoldedAt = nil
    }

    /// The system settled after a wake or a display change: the quiet start begins again and a
    /// pending first read no longer counts.
    mutating func didSettle(at now: ContinuousClock.Instant) {
        quietFrom = now
        firstFoldedAt = nil
    }

    /// Whether the breaker holds Automatic back at the given time.
    func isPaused(at now: ContinuousClock.Instant) -> Bool {
        pausedUntil(at: now) != nil
    }

    /// When the pause ends, or `nil` while fewer than ``Policy/breakerLimit`` passes are in the window.
    private func pausedUntil(at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        let inWindow = passes.filter { $0.duration(to: now) < Policy.breakerWindow }
        guard inWindow.count >= Policy.breakerLimit else {
            return nil
        }
        // The pass whose leaving brings the count below the limit.
        let deciding = inWindow[inWindow.count - Policy.breakerLimit]
        return deciding + Policy.breakerWindow
    }

    private mutating func endEpisode() {
        isInEpisode = false
        clearSince = nil
    }
}
