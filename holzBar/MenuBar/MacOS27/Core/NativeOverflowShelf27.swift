//
//  NativeOverflowShelf27.swift
//  holzBar
//

import CoreGraphics

nonisolated extension NativeOverflowReading27 {
    /// Whether the holzBar Shelf leaves out a covered item because macOS 27 shows it itself
    /// in its expanded overflow.
    ///
    /// False in every other case, so any doubt keeps the item listed: an item hidden from the
    /// Shelf that is not on the bar would be unreachable. Leaving it out needs the expanded
    /// state, a reading taken on the Shelf's own display, a known notch span, the item drawn by
    /// macOS and at most ``NativeOverflowState27/notchTolerance`` points of its frame under the notch.
    ///
    /// - Parameters:
    ///   - itemFrame: The item's own frame.
    ///   - isDrawn: Whether macOS draws the item on the active display (not stacked on the control).
    ///   - displayID: The display the Shelf opens on.
    func shelfOmits(itemFrame: CGRect, isDrawn: Bool, onDisplay displayID: CGDirectDisplayID) -> Bool {
        guard
            state == .expanded,
            self.displayID == displayID,
            isDrawn,
            let notchSpan,
            itemFrame.width > 4
        else {
            return false
        }
        let overlap = min(itemFrame.maxX, notchSpan.upperBound) - max(itemFrame.minX, notchSpan.lowerBound)
        return overlap <= NativeOverflowState27.notchTolerance
    }
}
