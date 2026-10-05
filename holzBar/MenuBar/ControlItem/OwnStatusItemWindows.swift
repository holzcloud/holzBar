//
//  OwnStatusItemWindows.swift
//  holzBar
//

import Cocoa

/// Recognises the windows of holzBar's own control items on macOS 26.
///
/// On macOS 26 every status item window is owned by Control Center, and the
/// application behind an item comes from the menu bar item service. When the
/// service has no answer, holzBar did not recognise even its own section
/// dividers: without them the item cache stayed empty, and the layout settings
/// and the holzBar Shelf showed "Loading menu bar items…" forever
/// (jordanbaird/Ice#687, jordanbaird/Ice#710, jordanbaird/Ice#711 and others).
///
/// Versions up to 0.0.6 recognised the windows by `NSWindow.windowNumber`, which on
/// macOS 26.7.1 is no window server identifier (1 << 32, 2 << 32, …), so it never
/// matched. The frame of the status item's window does match the Control Center
/// window (``StatusItemWindowFrame``), so holzBar recognises its control items by
/// their frames, without the service, Accessibility or window titles.
enum OwnStatusItemWindows {
    /// A weak reference to a control item's status item.
    private struct Entry {
        weak var statusItem: NSStatusItem?
    }

    /// The control items' status items.
    private static var entries = [ControlItem.Identifier: Entry]()

    /// Records the status item of the control item with the given identifier.
    static func register(_ statusItem: NSStatusItem, for identifier: ControlItem.Identifier) {
        entries[identifier] = Entry(statusItem: statusItem)
    }

    /// Returns, for each of the given window bounds as the window list describes them, the
    /// identifier of the control item whose window it is, or `nil` for a window that is
    /// none of holzBar's control items.
    ///
    /// The primary screen's height and the control items' frames are read once, so every
    /// window of one item list is compared against the same values. Each control item gets
    /// one window at most, the closest one: collapsed dividers next to each other lie within
    /// the tolerance of both windows (see ``StatusItemWindowFrame``).
    static func controlItems(forWindowBounds windowBounds: [CGRect]) -> [ControlItem.Identifier?] {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return windowBounds.map { _ in nil }
        }
        // A fixed order, so that a tie is decided the same way at every launch.
        let candidates = ControlItem.Identifier.allCases.compactMap { identifier -> (identifier: ControlItem.Identifier, frame: CGRect)? in
            guard
                let statusItem = entries[identifier]?.statusItem,
                statusItem.isVisible,
                let frame = statusItem.button?.window?.frame
            else {
                return nil
            }
            return (identifier, frame)
        }
        let assignment = StatusItemWindowFrame.assign(
            windowBounds: windowBounds,
            toAppKitFrames: candidates.map(\.frame),
            primaryScreenHeight: primaryScreenHeight
        )
        return assignment.map { index in
            index.map { candidates[$0].identifier }
        }
    }
}
