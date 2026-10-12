//
//  OwnStatusItemWindows.swift
//  holzBar
//

import Cocoa
import os

/// One of holzBar's own status items, as the window list of macOS 26 shows it.
enum OwnStatusItem: Equatable {
    /// A section divider.
    case control(ControlItem.Identifier)

    /// A status item with an autosave name of its own: a widget (`holzBar.Widget.<uuid>`).
    case autosaved(String)
}

/// Recognises the windows of holzBar's own status items on macOS 26: its control items and
/// its widgets.
///
/// On macOS 26 every status item window is owned by Control Center, and the
/// application behind an item is looked up through Accessibility
/// (``SourcePIDCache``). Before holzBar matched its control items by frame, a
/// lookup without an answer left even its own section dividers unrecognised:
/// without them the item cache stayed empty, and the layout settings and the
/// holzBar Shelf showed "Loading menu bar items…" forever (jordanbaird/Ice#687,
/// jordanbaird/Ice#710, jordanbaird/Ice#711 and others).
///
/// Versions up to 0.0.6 recognised the windows by `NSWindow.windowNumber`, which on
/// macOS 26.7.1 is no window server identifier (1 << 32, 2 << 32, …), so it never
/// matched. The frame of the status item's window does match the Control Center
/// window (``StatusItemWindowFrame``), so holzBar recognises its control items by
/// their frames, without Accessibility or window titles. A widget is matched the same way,
/// in the same assignment, so one window is never given to two items, a widget is never
/// attributed to another app and another app's window is never taken for a widget (D-17,
/// D-24).
enum OwnStatusItemWindows {
    /// A weak reference to one of holzBar's status items.
    private struct Entry {
        weak var statusItem: NSStatusItem?
    }

    /// The control items' status items.
    private static var entries = [ControlItem.Identifier: Entry]()

    /// The status items that are known by their autosave name, by that name.
    private static var autosavedEntries = [String: Entry]()

    /// Records the status item of the control item with the given identifier.
    static func register(_ statusItem: NSStatusItem, for identifier: ControlItem.Identifier) {
        entries[identifier] = Entry(statusItem: statusItem)
    }

    /// Records a status item that has the given autosave name, so its window is recognised
    /// as holzBar's own (a widget).
    static func register(_ statusItem: NSStatusItem, forAutosaveName autosaveName: String) {
        autosavedEntries[autosaveName] = Entry(statusItem: statusItem)
    }

    /// Forgets the status item with the given autosave name.
    static func unregister(autosaveName: String) {
        autosavedEntries[autosaveName] = nil
    }

    /// Returns, for each of the given window bounds as the window list describes them, which
    /// of holzBar's own status items draws the window, or `nil` for a window that is none of
    /// them.
    ///
    /// The primary screen's height and the items' frames are read once, so every window of one
    /// item list is compared against the same values. All of holzBar's items are assigned in
    /// one pass, the control items first (in their fixed order) and then the autosaved items
    /// (sorted by name): each item gets one window at most, the closest one, and each window
    /// one item at most. Collapsed dividers next to each other lie within the tolerance of both
    /// windows (see ``StatusItemWindowFrame``).
    static func ownItems(forWindowBounds windowBounds: [CGRect]) -> [OwnStatusItem?] {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return windowBounds.map { _ in nil }
        }
        var candidates = [(item: OwnStatusItem, frame: CGRect)]()
        // A fixed order, so that a tie is decided the same way at every launch.
        for identifier in ControlItem.Identifier.allCases {
            if let frame = windowFrame(of: entries[identifier]) {
                candidates.append((.control(identifier), frame))
            }
        }
        autosavedEntries = autosavedEntries.filter { $0.value.statusItem != nil }
        for name in autosavedEntries.keys.sorted() {
            if let frame = windowFrame(of: autosavedEntries[name]) {
                candidates.append((.autosaved(name), frame))
            }
        }
        let assignment = StatusItemWindowFrame.assign(
            windowBounds: windowBounds,
            toAppKitFrames: candidates.map(\.frame),
            primaryScreenHeight: primaryScreenHeight
        )
        return assignment.map { index in
            index.map { candidates[$0].item }
        }
    }

    /// Returns, for each of the given window bounds, the identifier of the control item whose
    /// window it is, or `nil` for a window that is none of holzBar's control items.
    static func controlItems(forWindowBounds windowBounds: [CGRect]) -> [ControlItem.Identifier?] {
        ownItems(forWindowBounds: windowBounds).map { item -> ControlItem.Identifier? in
            guard case .control(let identifier) = item else {
                return nil
            }
            return identifier
        }
    }

    /// The frame of the window of a status item that is visible and has one.
    private static func windowFrame(of entry: Entry?) -> CGRect? {
        guard
            let statusItem = entry?.statusItem,
            statusItem.isVisible,
            let frame = statusItem.button?.window?.frame
        else {
            return nil
        }
        return frame
    }
}

/// The names of holzBar's autosaved status items, by autosave name (a widget's name).
///
/// The item model is not isolated to the main actor and reads a name wherever an item list is
/// used, so the names live behind a lock and not in the main-actor registry above. A widget
/// registers its name when its status item is created or renamed and clears it when the item
/// is removed, so nothing stays here while the module is off (D-06).
nonisolated enum OwnStatusItemNames {
    private static let names = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Sets the name of the status item with the given autosave name, or clears it with `nil`.
    static func set(_ name: String?, forAutosaveName autosaveName: String) {
        names.withLock { state in
            state[autosaveName] = name
        }
    }

    /// Returns the name registered for the status item with the given autosave name.
    static func name(forAutosaveName autosaveName: String) -> String? {
        names.withLock { state in
            state[autosaveName]
        }
    }
}
