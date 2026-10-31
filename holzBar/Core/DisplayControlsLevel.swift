//
//  DisplayControlsLevel.swift
//  holzBar
//

import Foundation

/// The rules for a level of the Display controls module, a volume or a brightness from 0 to 1.
///
/// A value that comes from a slider, a key or the system is never used as it is: it is kept in
/// range here first, so a slip cannot set the volume to a value the system would reject, and
/// the whole percent the user reads is computed in one place.
nonisolated enum DisplayControlsLevel {
    /// The size of one step of the keyboard and VoiceOver: 5 percent.
    static let step = 0.05

    /// The lowest brightness the module sets, 2 percent, so that a slip of the slider cannot
    /// turn a display fully dark.
    static let minimumBrightness = 0.02

    /// How far a level read back may differ from the level requested and still agree: 2 percent.
    static let tolerance = 0.02

    /// A level kept between 0 and 1. A value that is not a number becomes 0.
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    /// A brightness kept between ``minimumBrightness`` and 1. A value that is not a number
    /// becomes the minimum.
    static func clampedBrightness(_ value: Double) -> Double {
        guard value.isFinite else {
            return minimumBrightness
        }
        return min(max(value, minimumBrightness), 1)
    }

    /// The whole percent of a level, rounded (62.5 becomes 63).
    static func percent(_ value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }

    /// A level moved by whole steps (negative to lower it), kept between 0 and 1 and rounded to
    /// two decimals so that many steps in a row do not drift.
    static func stepped(_ value: Double, by steps: Int) -> Double {
        let moved = clamped(value) + Double(steps) * step
        return (clamped(moved) * 100).rounded() / 100
    }

    /// Whether a level read back agrees with the level requested, within ``tolerance``. A value
    /// that is not a number agrees with nothing.
    static func agrees(_ requested: Double, _ readBack: Double) -> Bool {
        guard requested.isFinite, readBack.isFinite else {
            return false
        }
        return abs(requested - readBack) <= tolerance + 1e-9
    }
}
