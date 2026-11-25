//
//  ClosedNotchHeight.swift
//  holzBar
//

import Foundation

/// The height of the closed notch on a display with a notch (Phase 96, D-15).
///
/// The system's safe-area inset is the notch's height as the layout system sees it, and the menu
/// bar can be a point or so taller than that on some Macs (the inset reads 32 where the bar
/// measures 33). The closed shape has to be exactly as tall as the hardware notch, or it either
/// leaves a gap or overlaps a full-screen toolbar. There is no table of Mac models: the menu
/// bar's height is measured from the screen (the frame's top minus the visible frame's top) when
/// the display's geometry is worked out, never on a clock, and it counts only when it is between
/// the inset and ``maximumDifference`` points above it. Anything else (a menu bar that hides
/// automatically measures 0, an odd value, a bar shorter than the inset) falls back to the inset.
/// The "Display cutout" override of the Notch hub settings stays the escape hatch and is not
/// touched here.
nonisolated enum ClosedNotchHeight {
    /// How many points taller than the safe-area inset a measured menu bar may be to count.
    static let maximumDifference = 4.0

    /// The closed notch's height: the measured menu bar height when it lies between the inset
    /// and ``maximumDifference`` points above it, else the inset. A display without a usable
    /// inset (0, negative or not finite) gives 0: there is no notch, and the caller does not use
    /// the value.
    static func resolve(safeAreaTop: Double, menuBarHeight: Double) -> Double {
        guard safeAreaTop.isFinite, safeAreaTop > 0 else { return 0 }
        let difference = menuBarHeight - safeAreaTop
        guard difference.isFinite, difference >= 0, difference <= maximumDifference else { return safeAreaTop }
        return menuBarHeight
    }
}
