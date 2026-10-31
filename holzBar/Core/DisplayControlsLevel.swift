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

    /// The whole percent of a level, rounded (62.5 becomes 63).
    static func percent(_ value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }
}
