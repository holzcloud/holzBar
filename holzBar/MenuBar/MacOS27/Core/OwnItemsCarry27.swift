//
//  OwnItemsCarry27.swift
//  holzBar
//

/// Decides whether holzBar's own items of the last read stand in for a read that missed them.
///
/// macOS 27.2 can leave holzBar's own `AXExtrasMenuBar` out of an Accessibility read while
/// every other application answers. holzBar's process runs for as long as it reads, so its
/// items are still there: the last read's ones stand in, and the other applications' items
/// come from the fresh read. A read that returns the bar, even with no items in it, is an
/// answer and replaces them (the idea of Thaw's `mergingLiveCachedItems`, GPL-3.0, see
/// NOTICE).
nonisolated enum OwnItemsCarry27 {
    /// Whether the last read of holzBar's own items stands in for this one.
    ///
    /// - Parameters:
    ///   - barReturned: Whether this read returned holzBar's `AXExtrasMenuBar` with its children.
    ///   - lastReadItemCount: How many own items the last read that returned the bar found.
    static func carriesLastRead(barReturned: Bool, lastReadItemCount: Int) -> Bool {
        !barReturned && lastReadItemCount > 0
    }
}
