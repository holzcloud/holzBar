//
//  DDCLevel.swift
//  holzBar
//

import Foundation

/// Converts between a level from 0 to 1 and the raw value of a DDC control.
///
/// A monitor reports the largest raw value a control accepts (often 100, sometimes 50 or 255),
/// and the module's levels are always fractions of that maximum: the slider shows the share and
/// the monitor receives the matching raw value. The brightness floor keeps a slip from turning
/// the monitor's own backlight off.
nonisolated enum DDCLevel {
    /// The lowest brightness the module sets: 2 percent of the monitor's own maximum. It is the
    /// monitor's backlight that is scaled, never a software dimming.
    static let brightnessFloor = DisplayControlsLevel.minimumBrightness

    /// The raw value for a level. The level is kept between 0 and 1, raised to `floor`, scaled
    /// to `maximum` and rounded. With a floor above 0 and a maximum above 0 the result is at
    /// least 1, so a coarse scale (a maximum of 3) never rounds the floor down to off.
    static func raw(fromLevel level: Double, maximum: UInt16, floor: Double) -> UInt16 {
        let kept = max(DisplayControlsLevel.clamped(level), DisplayControlsLevel.clamped(floor))
        let scaled = (kept * Double(maximum)).rounded()
        var value = UInt16(min(max(scaled, 0), Double(maximum)))
        if floor > 0, maximum > 0 {
            value = max(value, 1)
        }
        return value
    }

    /// The level for a raw value, at most 1, or `nil` when the maximum is 0 (the monitor has no
    /// usable scale).
    static func level(raw: UInt16, maximum: UInt16) -> Double? {
        guard maximum > 0 else {
            return nil
        }
        return min(Double(raw) / Double(maximum), 1)
    }
}
