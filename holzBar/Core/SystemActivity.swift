//
//  SystemActivity.swift
//  holzBar
//

import Foundation

/// Whether the Mac is in use: the screen unlocked, the Mac awake and holzBar's login
/// session in front.
///
/// While the screen is locked, the Mac or its displays sleep, or another user's session is
/// in front, holzBar has nothing to do: the menu bar is not seen, and reading, moving or
/// capturing items then only fights macOS as it rearranges the bar. When that ends, and
/// when displays are connected or disconnected, the bar needs a moment to settle before
/// holzBar reads it again (``settleDelay``).
///
/// The state is fed with events (`SystemActivityMonitor`) and with the time of each, so it
/// can be tested without a clock.
nonisolated struct SystemActivity: Equatable {
    /// Something that changes whether the Mac is in use.
    nonisolated enum Event: Equatable, Sendable {
        case screenLocked
        case screenUnlocked
        case willSleep
        case didWake
        case sessionResigned
        case sessionBecameActive
        case displaysChanged
    }

    /// How long after the Mac is in use again, or the displays change, the menu bar is left
    /// to settle before holzBar reads it.
    static let settleDelay = Duration.seconds(2)

    /// Whether the screen is locked.
    private(set) var isLocked = false

    /// Whether the Mac or its displays sleep.
    private(set) var isAsleep = false

    /// Whether another login session is in front.
    private(set) var isSessionAway = false

    /// When the menu bar has settled after the last event that resumed or changed it.
    private(set) var settlesAt: ContinuousClock.Instant?

    /// Whether holzBar rests: the screen is locked, the Mac sleeps or the session is away.
    var isPaused: Bool {
        isLocked || isAsleep || isSessionAway
    }

    /// Records an event that happened at the given time.
    mutating func handle(_ event: Event, at now: ContinuousClock.Instant) {
        switch event {
        case .screenLocked:
            isLocked = true
        case .screenUnlocked:
            isLocked = false
            settlesAt = now + Self.settleDelay
        case .willSleep:
            isAsleep = true
        case .didWake:
            isAsleep = false
            settlesAt = now + Self.settleDelay
        case .sessionResigned:
            isSessionAway = true
        case .sessionBecameActive:
            isSessionAway = false
            settlesAt = now + Self.settleDelay
        case .displaysChanged:
            settlesAt = now + Self.settleDelay
        }
    }

    /// Whether holzBar may read the menu bar again at the given time: it does not rest, and
    /// the bar has settled after the last event that resumed or changed it.
    func settled(at now: ContinuousClock.Instant) -> Bool {
        guard !isPaused else {
            return false
        }
        guard let settlesAt else {
            return true
        }
        return now >= settlesAt
    }
}
