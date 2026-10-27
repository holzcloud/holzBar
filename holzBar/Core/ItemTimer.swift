//
//  ItemTimer.swift
//  holzBar
//

import Foundation

/// The state of one timer item: idle, counting down, or finished.
///
/// A pure value. The host asks it what to show and when to look again, and tells it the moment
/// every time; it keeps no clock of its own, so nothing here depends on how long a test takes.
nonisolated struct ItemTimer: Equatable, Sendable {
    /// The lengths the timer item offers, in minutes.
    static let minuteChoices = [1, 2, 5, 10, 15, 25, 30, 45, 60]
    /// The length a new timer starts with, in minutes.
    static let defaultMinutes = 5

    enum Phase: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case finished
    }

    private(set) var phase = Phase.idle

    /// A length kept within one minute and one hour.
    static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 1), 60)
    }

    var isRunning: Bool {
        if case .running = phase {
            return true
        }
        return false
    }

    /// A click: an idle timer starts, a running one is cancelled, a finished one is cleared.
    mutating func tap(minutes: Int, now: Date) {
        switch phase {
        case .idle:
            phase = .running(endsAt: now.addingTimeInterval(TimeInterval(Self.clampedMinutes(minutes) * 60)))
        case .running, .finished:
            phase = .idle
        }
    }

    /// Moves a running timer whose end has come to finished.
    ///
    /// - Returns: `true` when the timer just finished, so the host plays its sound once.
    mutating func advance(now: Date) -> Bool {
        guard case .running(let endsAt) = phase, now >= endsAt else {
            return false
        }
        phase = .finished
        return true
    }

    /// The text of the item: the chosen length while idle, the time left while running (rounded
    /// up, so it reads 0:01 until the very end), 0:00 once finished.
    func label(minutes: Int, now: Date) -> String {
        switch phase {
        case .idle:
            return Self.format(seconds: Self.clampedMinutes(minutes) * 60)
        case .running(let endsAt):
            let remaining = endsAt.timeIntervalSince(now).rounded(.up)
            return Self.format(seconds: remaining.isFinite ? Int(max(remaining, 0)) : 0)
        case .finished:
            return Self.format(seconds: 0)
        }
    }

    /// The moment the host has to look again, or `nil` when nothing changes by itself.
    ///
    /// While the item is seen, that is the moment the text changes (every whole second); while
    /// it is not, only the end matters.
    func nextWake(now: Date, isSeen: Bool) -> Date? {
        guard case .running(let endsAt) = phase else {
            return nil
        }
        let remaining = endsAt.timeIntervalSince(now)
        guard isSeen, remaining > 1 else {
            return endsAt
        }
        // The text shows ceil(remaining) seconds and changes when the remaining time drops to
        // the whole second below it.
        return endsAt.addingTimeInterval(-(remaining.rounded(.up) - 1))
    }

    /// `m:ss`, with minutes as long as they need.
    static func format(seconds: Int) -> String {
        let total = max(seconds, 0)
        let rest = total % 60
        return "\(total / 60):\(rest < 10 ? "0" : "")\(rest)"
    }
}
