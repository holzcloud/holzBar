//
//  ItemsAreaInputs27.swift
//  holzBar
//

import CoreGraphics

/// Everything the edge of the items area on macOS 27 is built from, besides the item cache
/// (`ItemHitTest27.itemsAreaLeftEdge`, `SplitShape27.leftEdge`).
///
/// A read asks the overlay to redraw only when these differ from the read before. The frames
/// are kept in order of position, not in the order a read found them: the system items are
/// collected from a dictionary, whose order changes from one read to the next, and two reads
/// of the same bar must compare equal.
nonisolated struct ItemsAreaInputs27: Equatable {
    let leftEdges: [CGDirectDisplayID: CGFloat]
    let drawnFramesByDisplay: [CGDirectDisplayID: [CGRect]]
    let systemItemFrames: [CGRect]
    let overflowButtonFrame: CGRect?

    init(
        leftEdges: [CGDirectDisplayID: CGFloat],
        drawnFramesByDisplay: [CGDirectDisplayID: [CGRect]],
        systemItemFrames: [CGRect],
        overflowButtonFrame: CGRect?
    ) {
        self.leftEdges = leftEdges
        self.drawnFramesByDisplay = drawnFramesByDisplay.mapValues(Self.ordered)
        self.systemItemFrames = Self.ordered(systemItemFrames)
        self.overflowButtonFrame = overflowButtonFrame
    }

    private static func ordered(_ frames: [CGRect]) -> [CGRect] {
        frames.sorted { ($0.minX, $0.minY, $0.width, $0.height) < ($1.minX, $1.minY, $1.width, $1.height) }
    }
}
