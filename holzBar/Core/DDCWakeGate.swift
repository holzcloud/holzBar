//
//  DDCWakeGate.swift
//  holzBar
//

import Foundation

/// Whether a DDC transfer may be sent, given when the Mac last woke or its displays last
/// changed (D-20, DISP-02).
///
/// A monitor that is coming back from sleep, or being reconfigured, drops or garbles requests,
/// so no read or write is sent until ``DDCTiming/wakeWait`` after the last such event. The
/// instants are ``ContinuousClock`` instants, like ``SystemActivity``, so the value can be
/// tested without a clock. The system activity monitor feeds it; the Display controls runtime
/// asks it before every survey, write and read-back, and the brightness keys ask it too.
nonisolated struct DDCWakeGate: Equatable, Sendable {
    /// The time of the last wake or display event, or `nil` when there was none.
    private(set) var lastEvent: ContinuousClock.Instant?

    /// Records a wake or display event. A later event extends the wait; an earlier one than the
    /// last never shortens it.
    mutating func record(at instant: ContinuousClock.Instant) {
        if let lastEvent, lastEvent >= instant {
            return
        }
        lastEvent = instant
    }

    /// Whether a transfer may be sent at the given time: exactly at the last event plus the
    /// wait, and always while there was no event.
    func isOpen(at instant: ContinuousClock.Instant) -> Bool {
        guard let opensAt else {
            return true
        }
        return instant >= opensAt
    }

    /// When the gate opens, or `nil` when there was no event.
    var opensAt: ContinuousClock.Instant? {
        lastEvent.map { $0 + DDCTiming.wakeWait }
    }
}
