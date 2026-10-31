//
//  FileDragWatch.swift
//  holzBar
//

import Foundation

/// Tells a file dragged to the notch from every other mouse drag, as a pure state machine from
/// mouse events to the hub's wishes.
///
/// The controller reads the drag pasteboard, the pointer and the panel and passes plain values;
/// nothing here touches AppKit. A drag is recognised by the drag pasteboard's change count: the
/// count at the last mouse-down is the baseline, and a drag whose count differs has put new
/// content on the pasteboard, which a plain mouse drag (a window, a selection, a slider) never
/// does. Whether that content has file URLs is asked once per drag, because reading the
/// pasteboard's types is not free (``needsInspection(changeCount:)``).
///
/// A mouse-down resets the state. A drop into holzBar's own window sends no mouse-up to a global
/// monitor, so a file drag could otherwise stay flagged for ever; the next press in another app
/// clears it.
nonisolated struct FileDragWatch: Equatable, Sendable {
    /// What an event asks of the hub.
    nonisolated struct Outcome: Equatable, Sendable {
        /// The action the drag asks for, or `nil` for nothing. ``NotchHubPolicy/decision(desired:pending:)``
        /// turns it into scheduling, given the action already waiting.
        var wish: NotchHubPolicy.HoverAction?
        /// The drag is over the open hub, so the File drop tab should show.
        var showDropTab: Bool
    }

    /// The change count at the last mouse-down.
    private var baseline: Int

    /// The change count whose pasteboard was inspected in this drag.
    private var inspectedCount: Int?

    /// Whether the current drag is known to carry file URLs.
    private(set) var isFileDrag = false

    /// Whether the open hub was opened by a file drag.
    private var hubWasOpenedByDrag = false

    /// Starts with the drag pasteboard's current change count.
    init(changeCount: Int) {
        baseline = changeCount
    }

    /// A mouse button went down in another app: the baseline becomes the current count, and the
    /// last drag is forgotten.
    mutating func pressed(changeCount: Int) {
        baseline = changeCount
        inspectedCount = nil
        isFileDrag = false
    }

    /// Whether the pasteboard must be asked for file URLs: no file drag is known, the count
    /// differs from the baseline, and this count has not been inspected in this drag. Only then
    /// is the answer passed to ``dragged(changeCount:hasFileURLs:pointerInZone:pointerInHub:hubIsOpen:)``.
    func needsInspection(changeCount: Int) -> Bool {
        !isFileDrag && changeCount != baseline && changeCount != inspectedCount
    }

    /// The mouse moved with the button down.
    ///
    /// With a file drag known, the pointer over the open hub gives ``Outcome/showDropTab``, and in
    /// the zone while the hub is closed gives the wish to open; anything else gives no wish (the
    /// hub does not close mid-drag). Without one there is never a wish.
    mutating func dragged(
        changeCount: Int,
        hasFileURLs: Bool,
        pointerInZone: Bool,
        pointerInHub: Bool,
        hubIsOpen: Bool
    ) -> Outcome {
        if needsInspection(changeCount: changeCount) {
            inspectedCount = changeCount
            isFileDrag = hasFileURLs
        }
        guard isFileDrag else {
            return Outcome(wish: nil, showDropTab: false)
        }
        if hubIsOpen {
            return Outcome(wish: nil, showDropTab: pointerInHub)
        }
        return Outcome(wish: pointerInZone ? .open : nil, showDropTab: false)
    }

    /// The button went up. The drag ends; the wish is to close only when this feature opened the
    /// hub and the pointer is not in it.
    mutating func released(hubIsOpen: Bool, pointerInHub: Bool) -> Outcome {
        isFileDrag = false
        inspectedCount = nil
        let closes = hubWasOpenedByDrag && hubIsOpen && !pointerInHub
        return Outcome(wish: closes ? .close : nil, showDropTab: false)
    }

    /// The hub opened; records whether a file drag opened it.
    mutating func hubOpened(byDrag: Bool) {
        hubWasOpenedByDrag = byDrag
    }

    /// The hub closed.
    mutating func hubClosed() {
        hubWasOpenedByDrag = false
    }
}
