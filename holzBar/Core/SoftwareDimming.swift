//
//  SoftwareDimming.swift
//  holzBar
//

import Foundation

/// What a monitor answered when asked for its brightness over DDC/CI, as far as the dimming rule
/// needs to know (Phase 96, D-25).
nonisolated enum DimmingDDCAnswer: Equatable, Sendable {
    /// The monitor is still being read; the answer is not known yet.
    case reading
    /// The monitor answered and has a brightness control, so its own slider does the job.
    case answersBrightness
    /// The monitor was never asked, does not answer, is indistinguishable from another, or
    /// answered without a brightness control.
    case noBrightness
}

/// The rules of software dimming: a dark overlay window over one display, the only dimming
/// mechanism (Phase 96, D-19, D-01; no gamma, no private call).
///
/// The darkening never exceeds ``maximum``, so a screen can never be made black by a slip. The
/// level of each display is kept by the display's UUID on this Mac only, and a stored dictionary
/// is data from outside, so it passes ``cleaned(_:)`` every time it is read.
nonisolated enum SoftwareDimming {
    /// The most the layer darkens a display, as the opacity of a black window: 90 percent, the
    /// floor that keeps the screen readable (D-19, T-96-22).
    static let maximum = 0.9

    /// The most displays that keep a level. Displays come and go and the stored value is data
    /// from outside, so the list is bounded.
    static let maximumDisplays = 32

    /// The longest display identifier kept, in UTF-8 bytes. A display UUID has 36.
    static let maximumIdentifierLength = 64

    /// A level held to 0 through ``maximum``; a negative level and a value that is not a number
    /// count as 0.
    static func clamped(_ level: Double) -> Double {
        guard level.isFinite else {
            return 0
        }
        return min(max(level, 0), maximum)
    }

    /// Reads the stored form: a dictionary of display UUID to level. Anything that is not a
    /// number, a key that is empty or too long, a level that clamps to 0 and everything past the
    /// limit (the first keys in sorted order are kept) is dropped; the others are clamped.
    static func cleaned(_ stored: [String: Any]) -> [String: Double] {
        var result = [String: Double]()
        for key in stored.keys.sorted() {
            guard
                result.count < maximumDisplays,
                !key.isEmpty,
                key.utf8.count <= maximumIdentifierLength,
                let number = stored[key] as? NSNumber
            else {
                continue
            }
            let level = clamped(number.doubleValue)
            if level > 0 {
                result[key] = level
            }
        }
        return result
    }

    /// Whether the card of a monitor offers the dim row (D-25): an external display that macOS
    /// cannot change itself, and, while External monitors (DDC) is on, only when the monitor does
    /// not answer DDC brightness. A monitor still being read hides the row until the read
    /// resolves, so the row does not flicker in and out.
    static func offersDimming(
        isExternal: Bool,
        macOSCanChange: Bool,
        ddcSwitchOn: Bool,
        answer: DimmingDDCAnswer
    ) -> Bool {
        guard isExternal, !macOSCanChange else {
            return false
        }
        guard ddcSwitchOn else {
            return true
        }
        return answer == .noBrightness
    }

    /// Whether hardware control has taken over from the dim layer of an external display: macOS
    /// can change it itself, or External monitors (DDC) is on and the monitor answered a DDC
    /// brightness read. The dim row is gone then (``offersDimming(isExternal:macOSCanChange:ddcSwitchOn:answer:)``),
    /// so the stored level is cleared with it: a layer never outlives the only control that can
    /// remove it. A monitor still being read, or not yet asked, keeps its layer.
    static func isSupersededByHardware(
        macOSCanChange: Bool,
        ddcSwitchOn: Bool,
        answer: DimmingDDCAnswer
    ) -> Bool {
        macOSCanChange || (ddcSwitchOn && answer == .answersBrightness)
    }

    /// Whether a layer window exists for a display: only for a level above 0, with the Notch hub
    /// and Display controls on and the display present (D-05).
    static func layerExists(level: Double, hubOn: Bool, moduleOn: Bool, displayPresent: Bool) -> Bool {
        hubOn && moduleOn && displayPresent && level > 0
    }
}
