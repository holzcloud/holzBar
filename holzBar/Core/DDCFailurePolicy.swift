//
//  DDCFailurePolicy.swift
//  holzBar
//

import Foundation

/// Turns what happens on the DDC bus into the events that count against the module's
/// ``PrivateFeatureGate``.
///
/// The part switches itself off after three failures in a row, so what counts as a failure
/// decides whether one monitor can switch off the part for another. A monitor that never
/// answered DDC (many do not, or have it turned off in their own menu) is not a failure of the
/// interface, and a single monitor with DDC/CI switched off in its own menu must never switch
/// the part off: a survey in which nothing answered counts only when at least one of the
/// displays it asked had answered earlier in this session, because only then does it say
/// something went wrong. A failed transfer counts on the same terms. A missing function is not this value's business: the gate makes the part
/// unavailable from the result of loading. The value remembers which displays answered, in
/// memory only, and makes no call.
nonisolated struct DDCFailurePolicy: Equatable, Sendable {
    /// What an observation means for the gate.
    enum Event: Equatable, Sendable {
        /// A valid reply: the gate's count of failures starts again.
        case success
        /// A failure that counts: the gate counts one more.
        case failure
        /// Nothing for the gate.
        case none
    }

    private var answeredDisplays = Set<UInt32>()

    /// The event of a survey. `tried` are the displays that were paired and asked, `answered`
    /// those of them that gave a valid reply. Any answer is a success. A survey with no answer
    /// is one failure only when at least one of the displays it asked had answered in an earlier
    /// survey of this session: a display that never answered (DDC/CI off in its menu, a TV, a
    /// dock that blocks DDC) counts for nothing, however often it is asked, and so does a survey
    /// that asked no display (every display without a pairing, or indistinguishable).
    mutating func surveyEnded(tried: Set<UInt32>, answered: Set<UInt32>) -> Event {
        let knownBefore = answeredDisplays
        answeredDisplays.formUnion(answered)
        if !answered.isEmpty {
            return .success
        }
        return tried.isDisjoint(with: knownBefore) ? .none : .failure
    }

    /// The event of one write or read to a display. A transfer that worked is a success and
    /// marks the display as answered; one that failed is a failure only for a display that
    /// answered before.
    mutating func transferEnded(display: UInt32, succeeded: Bool) -> Event {
        if succeeded {
            answeredDisplays.insert(display)
            return .success
        }
        return answeredDisplays.contains(display) ? .failure : .none
    }

    /// Whether the display gave a valid reply in this session.
    func hasAnswered(_ display: UInt32) -> Bool {
        answeredDisplays.contains(display)
    }
}
