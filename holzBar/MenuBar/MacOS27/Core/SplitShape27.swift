//
//  SplitShape27.swift
//  holzBar
//

import CoreGraphics
import Darwin

/// Geometry of the split menu bar shape on macOS 27, where there are no item windows to
/// measure: the trailing half starts where the run of items starts.
nonisolated enum SplitShape27 {
    /// Where the trailing half starts on a display, in CoreGraphics x, or `nil` when nothing
    /// is known there.
    ///
    /// The same edge as `ItemHitTest27.itemsAreaLeftEdge`, except that the edge remembered
    /// from the last read while the display was active is left out once MenuBarAgent's drawn
    /// frames for the display are known. Those frames are the whole current picture of a bar
    /// that is not active, while the remembered edge is only written while it is active, so
    /// it can still point at a hidden section that has been concealed again since. Hover
    /// hit-testing keeps the remembered edge and corrects itself on the next read; the shape
    /// would show the stale width the whole time.
    ///
    /// The cached items and system frames all lie on the active display, and the items area
    /// tells displays apart by x alone. Where a display sits above or below the active one,
    /// their x ranges overlap, so the frames are first kept to this display's rows too.
    static func leftEdge(
        displayBounds: CGRect,
        items: [ItemHitTest27.Item],
        concealedPIDs: Set<pid_t>,
        systemFrames: [CGRect],
        rememberedLeftEdge: CGFloat?,
        drawnFramesOnDisplay: [CGRect]
    ) -> CGFloat? {
        func isInThisDisplaysRows(_ frame: CGRect) -> Bool {
            displayBounds.minY...displayBounds.maxY ~= frame.midY
        }
        return ItemHitTest27.itemsAreaLeftEdge(
            displayBounds: displayBounds,
            items: items.filter { isInThisDisplaysRows($0.frame) },
            concealedPIDs: concealedPIDs,
            systemFrames: systemFrames.filter(isInThisDisplaysRows),
            rememberedLeftEdge: drawnFramesOnDisplay.isEmpty ? rememberedLeftEdge : nil,
            drawnFramesOnDisplay: drawnFramesOnDisplay
        )
    }

    /// The bounds of the trailing half in the shape's rectangle, or `.zero`, which draws the
    /// full shape, when the half does not fit between the edge and the rectangle's right end.
    ///
    /// `edge` is `leftEdge` in the rectangle's x (minus the screen's minX), and `rect` is the
    /// shape's rectangle after the inset. A round trailing end cap moves `rect.maxX` with the
    /// inset but not the edge, so with the inset it comes off for either cap; without it the
    /// half starts 7 points left of the edge. The window-width path before macOS 27 lands on
    /// the same positions.
    static func trailingBounds(edge: CGFloat, in rect: CGRect, isInset: Bool, insetAmount: CGFloat) -> CGRect {
        let minX = isInset ? edge + 4 - insetAmount : edge - 7
        // A half narrower than it is high cannot hold its end caps, and one that starts left of
        // the rectangle would leave it.
        guard minX >= rect.minX, minX < rect.maxX - rect.height else {
            return .zero
        }
        return CGRect(x: minX, y: rect.minY, width: rect.maxX - minX, height: rect.height)
    }
}
