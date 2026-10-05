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

    /// Returns the identifier of the control item whose window has the given bounds, as
    /// the window list describes them, or `nil` when the window is none of holzBar's
    /// control items.
    static func controlItem(forWindowBounds bounds: CGRect) -> ControlItem.Identifier? {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }
        return entries.first { _, entry in
            guard
                let statusItem = entry.statusItem,
                statusItem.isVisible,
                let frame = statusItem.button?.window?.frame
            else {
                return false
            }
            return StatusItemWindowFrame.matches(bounds, appKitFrame: frame, primaryScreenHeight: primaryScreenHeight)
        }?.key
    }
}
