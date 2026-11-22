//
//  DisplayCutout.swift
//  holzBar
//

import Foundation

/// The kind of camera cutout at the top of a display.
///
/// A MacBook has either the notch (a wide, shallow cutout, about 185 by 32 points on a 1512-wide
/// display, measured on a notch Mac) or Apple's Dynamic Island (a small pill, about 59 by 40
/// points, cited from Vorssaint #3998 and not yet measured here), or neither. The hub lays itself
/// out differently around each: it continues the notch, and it sits below the island (Phase 93,
/// D-03).
///
/// The kind is worked out from public API only: `NSScreen.safeAreaInsets` and the two unobscured
/// areas `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, passed in as plain numbers by
/// ``classify(displayWidth:leftAreaWidth:rightAreaWidth:safeAreaTop:)``. The raw values may be
/// stored, so a new case goes at the end.
nonisolated enum DisplayCutout: Int, CaseIterable, Sendable {
    /// No cutout: a display without a camera housing, or one that reports none.
    case none = 0
    /// The notch.
    case notch = 1
    /// Apple's Dynamic Island.
    case island = 2

    /// A cutout whose width divided by the safe-area height is below this is an island; the
    /// notch is about 5.8 times as wide as it is tall, the island about 1.5 times.
    static let islandRatioLimit: Double = 3

    /// The kind of cutout from what the system reports.
    ///
    /// - Parameters:
    ///   - displayWidth: The display's width in points.
    ///   - leftAreaWidth: The width of `auxiliaryTopLeftArea`, or `nil` where there is none.
    ///   - rightAreaWidth: The width of `auxiliaryTopRightArea`, or `nil` where there is none.
    ///   - safeAreaTop: The top of `safeAreaInsets`, the cutout's height.
    /// - Returns: ``none`` for a missing area or safe area, or a value that is not a number or
    ///   leaves no cutout between the areas; otherwise ``island`` where the cutout's width is
    ///   less than ``islandRatioLimit`` times the safe-area height, and ``notch`` where it is not.
    static func classify(
        displayWidth: Double,
        leftAreaWidth: Double?,
        rightAreaWidth: Double?,
        safeAreaTop: Double
    ) -> DisplayCutout {
        guard
            safeAreaTop.isFinite, safeAreaTop > 0,
            let leftAreaWidth, let rightAreaWidth,
            leftAreaWidth.isFinite, rightAreaWidth.isFinite
        else {
            return .none
        }
        let width = displayWidth - leftAreaWidth - rightAreaWidth
        guard width.isFinite, width > 0 else {
            return .none
        }
        return width / safeAreaTop < islandRatioLimit ? .island : .notch
    }
}
