//
//  DividerPlausibility.swift
//  holzBar
//

import Foundation

/// Whether a read of holzBar's two divider items can be believed (macOS 14 to 26).
///
/// Right after a display change, a wake or an unlock, macOS can report holzBar's Hidden divider on
/// the wrong side of the Clock for a moment. The Clock is pinned at the right end of the bar, so
/// no divider can end right of its left edge. Acting on such a read puts every item in Hidden: the
/// section lookup would store that as the user's arrangement and a restore would move items there.
/// holzBar moves and records nothing from a read that fails this rule, and reads again with the
/// next event.
///
/// The dividers are not compared with each other: a swapped pair stays left of the Clock and is
/// repaired by `enforceControlItemOrder`, which a stricter rule would stop.
nonisolated enum DividerPlausibility {
    /// A horizontal extent of a window on screen, in points.
    struct Span: Equatable, Sendable {
        let minX: Double
        let maxX: Double
    }

    /// How far right of the Clock's left edge a divider may end, in points. The same value as the
    /// tolerance of a move, because window bounds carry sub-point values.
    static let tolerance: Double = 2

    /// Whether the read can be believed. A read without a Clock is plausible, so a missing Clock
    /// never blocks holzBar.
    static func isPlausible(hidden: Span, alwaysHidden: Span?, clock: Span?) -> Bool {
        guard let clock else {
            return true
        }
        let limit = clock.minX + tolerance
        guard hidden.maxX <= limit else {
            return false
        }
        if let alwaysHidden, alwaysHidden.maxX > limit {
            return false
        }
        return true
    }
}
