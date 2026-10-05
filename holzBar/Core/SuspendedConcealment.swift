//
//  SuspendedConcealment.swift
//  holzBar
//

import Foundation

/// Whether holzBar is meant to conceal while a suspension lifts every assertion for a moment.
///
/// On macOS 27 a bridged click on a system item and a relayout for the notch release every
/// assertion for a few hundred milliseconds, and `isConcealing` is `false` meanwhile. What
/// follows concealment as a state, such as the capture badge on holzBar's icon, reads
/// ``conceals(isConcealing:)`` instead, so it does not go away and come back on every bridged
/// click.
nonisolated struct SuspendedConcealment: Equatable, Sendable {
    /// Whether the suspension under way began while concealing.
    private(set) var liftsConcealment = false

    /// Records a suspension that begins. One begun during another keeps what that one lifted.
    mutating func begin(isConcealing: Bool) {
        liftsConcealment = liftsConcealment || isConcealing
    }

    /// Records that the suspension ended, right before concealment is worked out again.
    mutating func end() {
        liftsConcealment = false
    }

    /// Whether concealment is meant to be on: it is, or only a suspension lifts it.
    func conceals(isConcealing: Bool) -> Bool {
        isConcealing || liftsConcealment
    }
}
