//
//  FoldedItemMemory27.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// Remembers the items macOS 27.2 folds behind its overflow control, which Accessibility then
/// no longer reports.
///
/// Measured on macOS 27.2 (build 26B123) with the control collapsed: the apps whose items were
/// folded are not in `AXExtrasMenuBar` at all, neither with a frame nor stacked against the
/// control (`Scripts/macos27/overflow-state-probe.swift`). Expanded, they are all back. So an
/// item that was read before and is missing now, while the control is still there and its
/// process still runs, is taken to be folded and is kept listed (not drawn, in its saved
/// section). The memory is dropped when the control is gone, per display change, and item by
/// item when the process quits or the item is read again (the fresh read wins).
///
/// The memory is generic over what the caller keeps per item, so the decision stays free of
/// Accessibility types.
nonisolated struct FoldedItemMemory27<Payload> {
    /// One item as the memory sees it.
    struct Candidate {
        /// The item's synthetic window identifier (`SyntheticWindowID27`), which is also its identity.
        let windowID: UInt32
        let ownerPID: pid_t
        /// Where the item was last read, to tell whether it was on the display.
        let frame: CGRect
        let payload: Payload
    }

    /// The most items the memory keeps, so a misbehaving process cannot make it grow.
    static var limit: Int { 128 }

    /// Everything the memory knows: the last read's items first, then the carried ones.
    private var known = [Candidate]()
    private var freshIDs = Set<UInt32>()
    private var displayID: CGDirectDisplayID?

    init() {}

    /// Takes one finished read of the bar.
    ///
    /// - Parameters:
    ///   - seen: The items the read reported. The caller leaves out holzBar's own items,
    ///     control items and the system's own (MenuBarAgent) items.
    ///   - controlPresent: Whether the overflow control is on the bar being read.
    ///   - running: The processes that run now.
    ///   - displayID: The display with the active menu bar.
    ///   - displayBounds: Its bounds. An item whose frame is elsewhere was never on this bar and is not remembered.
    mutating func update(
        seen: [Candidate],
        controlPresent: Bool,
        running: Set<pid_t>,
        displayID: CGDirectDisplayID?,
        displayBounds: CGRect?
    ) {
        if displayID != self.displayID {
            known = []
            self.displayID = displayID
        }
        let onBar = seen.filter { displayBounds?.intersects($0.frame) ?? true }
        freshIDs = Set(seen.map(\.windowID))
        guard controlPresent else {
            // Nothing is folded without the control: what is missing is gone.
            known = Array(onBar.prefix(Self.limit))
            return
        }
        var next = onBar
        var taken = Set(onBar.map(\.windowID))
        for candidate in known where !freshIDs.contains(candidate.windowID) && running.contains(candidate.ownerPID) {
            if taken.insert(candidate.windowID).inserted {
                next.append(candidate)
            }
        }
        if next.count > Self.limit {
            // Fresh items come first and stay; the oldest carried ones go.
            next = Array(next.prefix(Self.limit))
        }
        known = next
    }

    /// The items to list as folded: remembered, and not in the last read.
    var folded: [Candidate] {
        known.filter { !freshIDs.contains($0.windowID) }
    }
}
