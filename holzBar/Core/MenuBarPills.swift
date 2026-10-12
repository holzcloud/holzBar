//
//  MenuBarPills.swift
//  holzBar
//

import Foundation

/// The pure geometry of the menu bar shapes, in plain `Double` x coordinates of the overlay's
/// rectangle (the screen's x minus the screen's left edge).
nonisolated enum MenuBarPills {
    /// The space between two neighbouring shapes, in points.
    static let gap: Double = 4

    /// One of holzBar's section dividers on this display.
    ///
    /// A collapsed divider is 10 000 points long, so its middle says nothing: only a divider
    /// that shows its section marks a boundary between two sections.
    nonisolated struct Divider: Equatable, Sendable {
        /// The x span of the divider's window.
        let span: ClosedRange<Double>
        /// Whether the divider shows its section.
        let showsSection: Bool

        init(span: ClosedRange<Double>, showsSection: Bool) {
            self.span = span
            self.showsSection = showsSection
        }

        /// The middle of the divider's span.
        fileprivate var middle: Double {
            (span.lowerBound + span.upperBound) / 2
        }
    }

    /// The spans of the shapes the Sections look draws for the items area, left to right.
    ///
    /// `itemsArea` is the span of the trailing shape of Paired. Without a hidden divider on
    /// this display the result is `nil`, and the caller draws Paired. While the hidden
    /// section is collapsed the items area is one shape. A hidden section that shows splits
    /// the items area at the middle of its divider, and an always-hidden section that shows
    /// splits it again at the middle of its own divider; the shapes are `gap` apart. Every
    /// bound is clamped into the items area, a span narrower than `minimumWidth` is left out,
    /// and nothing left gives `nil`. The spans never overlap.
    static func sectionSpans(
        itemsArea: ClosedRange<Double>,
        hiddenDivider: Divider?,
        alwaysHiddenDivider: Divider?,
        minimumWidth: Double
    ) -> [ClosedRange<Double>]? {
        guard let hiddenDivider else {
            return nil
        }

        // The boundaries between the sections, from the right: the middle of a divider that
        // shows its section.
        var boundaries: [Double] = []
        if hiddenDivider.showsSection {
            boundaries.append(hiddenDivider.middle)
            if let alwaysHiddenDivider, alwaysHiddenDivider.showsSection {
                boundaries.append(alwaysHiddenDivider.middle)
            }
        }

        // Cut the items area at every boundary, left to right.
        let half = gap / 2
        let cuts = boundaries.sorted()
        var lowers = [itemsArea.lowerBound]
        var uppers: [Double] = []
        for cut in cuts {
            uppers.append(cut - half)
            lowers.append(cut + half)
        }
        uppers.append(itemsArea.upperBound)

        var spans: [ClosedRange<Double>] = []
        for (lower, upper) in zip(lowers, uppers) {
            let clampedLower = min(max(lower, itemsArea.lowerBound), itemsArea.upperBound)
            let clampedUpper = min(max(upper, itemsArea.lowerBound), itemsArea.upperBound)
            guard clampedUpper - clampedLower >= minimumWidth else {
                continue
            }
            spans.append(clampedLower...clampedUpper)
        }
        return spans.isEmpty ? nil : spans
    }
}
