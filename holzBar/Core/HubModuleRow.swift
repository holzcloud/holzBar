//
//  HubModuleRow.swift
//  holzBar
//

import Foundation

/// How the Notch hub's row of module buttons fits the island (concept section 10b, "Layout").
///
/// Every enabled module and the Overview is one round button in one row. The row never has a More
/// menu. It fits in this order: the hub first widens, from its base width up to the most the
/// display allows; then all buttons step down through ``DesignTokens/Island/buttonSizes``; and
/// only when the smallest buttons do not fit in the widest hub does the row scroll sideways.
nonisolated enum HubModuleRow {
    /// How the row is drawn.
    nonisolated struct Fit: Equatable, Sendable {
        /// The diameter of every button, in points.
        var buttonSize: Double
        /// The width of the whole island, in points.
        var hubWidth: Double
        /// Whether the row scrolls horizontally because even the smallest buttons do not fit.
        var scrolls: Bool
    }

    /// The width of a row of `count` buttons of `buttonSize` with the gaps between them; zero
    /// without buttons.
    static func rowWidth(count: Int, buttonSize: Double) -> Double {
        guard count > 0 else {
            return 0
        }
        return Double(count) * buttonSize + Double(count - 1) * DesignTokens.Island.buttonGap
    }

    /// The button size, the hub's width and whether the row scrolls, for `count` buttons in a hub
    /// that is `baseWidth` wide and may grow to `maxWidth`.
    ///
    /// A `maxWidth` that is not a number counts as the base width; a maximum below the base width
    /// lowers the base width to it, so a narrow display shrinks the hub instead of overflowing it.
    static func fit(count: Int, baseWidth: Double, maxWidth: Double) -> Fit {
        let steps = DesignTokens.Island.buttonSizes.isEmpty ? [30] : DesignTokens.Island.buttonSizes
        let base = baseWidth.isNaN ? DesignTokens.Island.baseWidth : baseWidth
        let widest = maxWidth.isNaN ? base : max(maxWidth, 0)
        let narrowBase = min(base, widest)
        guard count > 0 else {
            return Fit(buttonSize: steps[0], hubWidth: narrowBase, scrolls: false)
        }
        let inset = 2 * (DesignTokens.Island.openTopRadius + DesignTokens.Island.sidePadding)
        for (index, size) in steps.enumerated() {
            let needed = rowWidth(count: count, buttonSize: size) + inset
            guard needed <= widest else {
                continue
            }
            // The first size widens the hub as far as it needs; a smaller size means the hub is
            // already as wide as it can be.
            let hubWidth = index == 0 ? max(narrowBase, needed) : widest
            return Fit(buttonSize: size, hubWidth: hubWidth, scrolls: false)
        }
        return Fit(buttonSize: steps[steps.count - 1], hubWidth: widest, scrolls: true)
    }
}
