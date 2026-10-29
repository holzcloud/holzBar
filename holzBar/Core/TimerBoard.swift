//
//  TimerBoard.swift
//  holzBar
//

import Foundation

/// One timer on a ``TimerBoard``.
nonisolated struct TimerItem: Identifiable, Equatable, Sendable {
    /// What the timer measures.
    nonisolated enum Kind: Equatable, Sendable {
        /// A length of time in seconds; it can be paused and restarted.
        case length(Double)
        /// A countdown to a moment of the wall clock.
        case moment(Date)
    }

    /// Where the timer is in its life.
    nonisolated enum State: Equatable, Sendable {
        /// Running from `start` to `end`.
        case running(start: Date, end: Date)
        /// Paused with `remaining` of `total` seconds left.
        case paused(remaining: Double, total: Double)
        /// Ended (or was found ended) at the given moment.
        case finished(at: Date)
    }

    let id: UUID
    var label: String
    let kind: Kind
    var state: State
}

/// The timers of one board, as plain values and explicit dates: no clock, no I/O.
///
/// Every function takes the moment it works at as a parameter, so the rules can be tested
/// without waiting. A timer stores the `Date` it ends (the wall clock), so a countdown to a
/// moment and a length of time follow one rule; setting the Mac's clock moves them both.
/// A late ending, one that happened more than ``lateTolerance`` seconds before the board
/// noticed it, is reported apart so that the app can skip the sound for it.
nonisolated struct TimerBoard: Equatable, Sendable {
    /// The most timers on a board at once (the maintainer's choice: eight).
    static let maximumItems = 8
    /// The shortest length of a timer, in seconds.
    static let minimumLength: Double = 1
    /// The longest length of a timer, in seconds: 99 hours, 59 minutes and 59 seconds.
    static let maximumLength: Double = 359_999
    /// The least time between now and a moment a countdown may end at, in seconds.
    static let minimumLead: Double = 2
    /// The farthest a countdown's moment may lie ahead: 366 days, in seconds.
    static let maximumDistance: Double = 366 * 24 * 60 * 60
    /// The longest label, in characters.
    static let maximumLabelLength = 40
    /// How late, in seconds, an ending may be noticed and still ring. An ending noticed later
    /// than this (the Mac slept, holzBar was not running) is marked finished without a sound.
    static let lateTolerance: Double = 15

    /// Why a timer could not be started.
    nonisolated enum Refusal: Equatable, Sendable {
        case full
        case lengthOutOfRange
        case momentTooSoon
        case momentTooFar
    }

    /// The result of starting a timer.
    nonisolated enum StartResult: Equatable, Sendable {
        case started(UUID)
        case refused(Refusal)
    }

    /// The timers that ended since the last look, in the order they ended.
    struct Finished: Equatable, Sendable {
        /// Ended at most ``TimerBoard/lateTolerance`` seconds ago: the sound rings.
        var rang: [UUID] = []
        /// Ended earlier: finished silently.
        var missed: [UUID] = []
    }

    /// The timers in the order they were added.
    private(set) var items: [TimerItem] = []

    /// Starts a timer for a length of time, running from `now`.
    ///
    /// The length must be finite and between ``minimumLength`` and ``maximumLength``; otherwise
    /// the start is refused and the board does not change.
    @discardableResult
    mutating func startLength(_ seconds: Double, label: String, now: Date, id: UUID = UUID()) -> StartResult {
        guard seconds.isFinite, seconds >= Self.minimumLength, seconds <= Self.maximumLength else {
            return .refused(.lengthOutOfRange)
        }
        items.append(
            TimerItem(
                id: id,
                label: Self.cleanLabel(label),
                kind: .length(seconds),
                state: .running(start: now, end: now.addingTimeInterval(seconds))
            )
        )
        return .started(id)
    }

    /// The seconds left on a timer at `now`, or `nil` for an unknown timer.
    func remaining(of id: UUID, now: Date) -> Double? {
        guard let item = items.first(where: { $0.id == id }) else {
            return nil
        }
        switch item.state {
        case .running(_, let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining, _): return remaining
        case .finished: return 0
        }
    }

    /// The earliest end among the running timers, or `nil` when none runs.
    var nextDeadline: Date? {
        items.compactMap { item -> Date? in
            if case .running(_, let end) = item.state {
                return end
            }
            return nil
        }
        .min()
    }

    /// Marks every running timer whose end is not after `now` as finished at its end, and
    /// reports which of them ring and which ended too long ago to ring. A timer is reported
    /// once.
    mutating func collectFinished(now: Date) -> Finished {
        var ended = [(id: UUID, end: Date)]()
        for index in items.indices {
            if case .running(_, let end) = items[index].state, end <= now {
                items[index].state = .finished(at: end)
                ended.append((items[index].id, end))
            }
        }
        var result = Finished()
        for entry in ended.sorted(by: { $0.end < $1.end }) {
            if now.timeIntervalSince(entry.end) <= Self.lateTolerance {
                result.rang.append(entry.id)
            } else {
                result.missed.append(entry.id)
            }
        }
        return result
    }

    /// A label as the board keeps it: trimmed, line breaks turned into spaces, cut to
    /// ``maximumLabelLength`` characters. An empty label stays empty.
    static func cleanLabel(_ text: String) -> String {
        let flat = String(text.map { $0.isNewline ? " " : $0 })
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumLabelLength)).trimmingCharacters(in: .whitespaces)
    }
}
