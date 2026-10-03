//
//  SliderValue.swift
//  holzBar
//

import Foundation

/// The value math of `HolzBarSlider`: fractions, snapping and arrow-key steps.
///
/// Every function works on `Double`; the slider converts its value type to and from it.
nonisolated enum SliderValue {
    /// The value at `fraction` (0 is the lower bound, 1 the upper one) of `bounds`,
    /// snapped to `step` when there is one. Fractions outside 0...1 are clamped.
    static func value(atFraction fraction: Double, in bounds: ClosedRange<Double>, step: Double?) -> Double {
        let clamped = min(max(fraction, 0), 1)
        let raw = bounds.lowerBound + clamped * (bounds.upperBound - bounds.lowerBound)
        return snapped(raw, in: bounds, step: step)
    }

    /// Where `value` lies in `bounds`, from 0 to 1. An empty range gives 0.
    static func fraction(of value: Double, in bounds: ClosedRange<Double>) -> Double {
        let length = bounds.upperBound - bounds.lowerBound
        guard length > 0 else {
            return 0
        }
        return min(max((value - bounds.lowerBound) / length, 0), 1)
    }

    /// `value` rounded to the nearest multiple of `step` counted from the lower bound,
    /// and kept in `bounds`. Without a (positive) step the value is only clamped.
    static func snapped(_ value: Double, in bounds: ClosedRange<Double>, step: Double?) -> Double {
        var result = value
        if let step, step > 0 {
            let steps = ((value - bounds.lowerBound) / step).rounded()
            // Rounded to ten decimal places, which removes the floating-point noise of
            // the multiplication (3 × 0.1 is 0.30000000000000004, not 0.3).
            result = ((bounds.lowerBound + steps * step) * 1e10).rounded() / 1e10
        }
        return min(max(result, bounds.lowerBound), bounds.upperBound)
    }

    /// `value` moved by `count` steps (negative moves down), as the arrow keys do.
    /// Without a step one step is one hundredth of the range. The result stays in `bounds`.
    static func increment(_ value: Double, by count: Int, in bounds: ClosedRange<Double>, step: Double?) -> Double {
        let length = bounds.upperBound - bounds.lowerBound
        let stepSize: Double
        if let step, step > 0 {
            stepSize = step
        } else {
            stepSize = length / 100
        }
        let moved = value + Double(count) * stepSize
        return snapped(moved, in: bounds, step: step)
    }
}
