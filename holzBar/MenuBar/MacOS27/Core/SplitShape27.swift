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
    static func leftEdge(
        displayBounds: CGRect,
        items: [ItemHitTest27.Item],
        concealedPIDs: Set<pid_t>,
        systemFrames: [CGRect],
        rememberedLeftEdge: CGFloat?,
        drawnFramesOnDisplay: [CGRect]
    ) -> CGFloat? {
        ItemHitTest27.itemsAreaLeftEdge(
            displayBounds: displayBounds,
            items: items,
            concealedPIDs: concealedPIDs,
            systemFrames: systemFrames,
            rememberedLeftEdge: drawnFramesOnDisplay.isEmpty ? rememberedLeftEdge : nil,
            drawnFramesOnDisplay: drawnFramesOnDisplay
        )
    }
}
