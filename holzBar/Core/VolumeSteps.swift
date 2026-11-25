//
//  VolumeSteps.swift
//  holzBar
//

import Foundation

/// Turns the stream of levels an output reads back into what is worth showing: key-sized steps,
/// mute changes and the ends of the range (D-10).
///
/// Apple's volume key moves the level by 1/16 and Option-Shift by 1/64; AirPods' adaptive volume
/// drifts the level by less than that, all the time. A reading therefore reports only when it is
/// at least a quarter step (1/64) from the level last reported, so a slow drift never flashes and
/// never adds up to a flash until it has really moved that far. Reaching 0 or 1 reports even when
/// the step is smaller, because the ends are where a held key stops. The first reading, and the
/// first one after ``reset()``, is a baseline and reports nothing. The value does no reading and no
/// waiting: the caller passes what the output says.
nonisolated struct VolumeSteps: Equatable, Sendable {
    /// 1/64: the smallest step of a key (Option-Shift).
    static let quarterStep = 1.0 / 64

    /// What changed.
    nonisolated enum Change: Equatable, Sendable {
        /// The level moved by a step or reached an end; the percentage is the level shown.
        case level(percent: Int)
        /// The output was muted, or a step was made while it is muted.
        case muted
        /// The output was unmuted; the percentage is its level.
        case unmuted(percent: Int)
    }

    private var lastLevel: Double?
    private var lastMuted = false

    init() {}

    /// Offers a reading and answers what to show, if anything. A level that cannot be read (`nil`,
    /// or not a finite number) reports nothing and keeps the baseline. An output without a mute
    /// reads as not muted.
    mutating func offer(level: Double?, isMuted: Bool?) -> Change? {
        guard let level, level.isFinite else {
            return nil
        }
        let muted = isMuted ?? false
        guard let last = lastLevel else {
            lastLevel = level
            lastMuted = muted
            return nil
        }
        if muted != lastMuted {
            lastMuted = muted
            lastLevel = level
            return muted ? .muted : .unmuted(percent: Self.percent(level))
        }
        guard level != last else {
            return nil
        }
        let reachesEnd = level <= 0 || level >= 1
        guard abs(level - last) >= Self.quarterStep || reachesEnd else {
            return nil
        }
        lastLevel = level
        return muted ? .muted : .level(percent: Self.percent(level))
    }

    /// Forgets the last reading: the next one is a baseline. Called when the default output
    /// changes.
    mutating func reset() {
        lastLevel = nil
        lastMuted = false
    }

    /// The level as a whole percentage, rounded half away from zero and kept in 0 to 100; a value
    /// that is not a finite number is 0.
    static func percent(_ level: Double) -> Int {
        guard level.isFinite else {
            return 0
        }
        return Int(min(max((level * 100).rounded(), 0), 100))
    }
}
