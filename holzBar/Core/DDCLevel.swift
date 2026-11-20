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

    /// The lowest contrast the module sets: 2 percent of the monitor's own maximum, so a slip
    /// cannot make the screen unreadable.
    static let contrastFloor = DisplayControlsLevel.minimumBrightness

    /// The lowest level the module sets for a control: the floor for brightness and contrast, 0
    /// for volume and mute.
    static func floor(for control: DDCControl) -> Double {
        switch control {
        case .brightness: brightnessFloor
        case .contrast: contrastFloor
        case .volume, .mute: 0
        }
    }

    /// Whether the raw value of the mute control means muted. Only 1 does: a monitor that has
    /// never been muted may report 0 (a Samsung S34C65xV does), and 2 is unmuted.
    static func isMuted(raw: UInt16) -> Bool {
        raw == 1
    }

    /// The raw value that mutes (1) or unmutes (2) a monitor, as MCCS 2.x defines it.
    static func muteRaw(_ muted: Bool) -> UInt16 {
        muted ? 1 : 2
    }

    /// The raw value that is actually written for a control, or `nil` when none may be. Brightness,
    /// contrast and volume are ranges: the value is kept at or below the maximum the monitor
    /// reported. Mute is not a range but two fixed codes, 1 (mute) and 2 (unmute): it is written
    /// as exactly that, whatever maximum the monitor reported (one that reports 1 would otherwise
    /// turn "unmute" into "mute"), and any other value is refused.
    static func writable(raw: UInt16, for control: DDCControl, maximum: UInt16) -> UInt16? {
        switch control {
        case .mute:
            return raw == muteRaw(true) || raw == muteRaw(false) ? raw : nil
        case .brightness, .contrast, .volume:
            return min(raw, maximum)
        }
    }

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
