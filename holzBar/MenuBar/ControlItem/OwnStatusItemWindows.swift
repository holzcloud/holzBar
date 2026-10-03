//
//  OwnStatusItemWindows.swift
//  holzBar
//

import CoreGraphics
import Foundation
import os

/// The window identifiers of holzBar's own status items.
///
/// On macOS 26 every status item window is owned by Control Center, and the
/// application behind an item comes from the menu bar item service. When the
/// service has no answer, holzBar did not recognise even its own section
/// dividers: without them the item cache stayed empty, and the layout settings
/// and the holzBar Shelf showed "Loading menu bar items…" forever
/// (jordanbaird/Ice#687, jordanbaird/Ice#710, jordanbaird/Ice#711 and others).
/// holzBar knows its own windows, so it recognises them by these identifiers.
///
/// The item cache reads them off the main thread, so they live behind a lock.
nonisolated enum OwnStatusItemWindows {
    private static let windowIDs = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: CGWindowID]())

    /// Records the window of the given owner, replacing its previous one.
    static func set(_ windowNumber: Int?, for owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        // A window number above `UInt32.max` traps a plain conversion
        // (jordanbaird/Ice#989).
        let windowID = windowNumber.flatMap { CGWindowID(exactly: $0) }
        windowIDs.withLock { $0[key] = windowID }
    }

    /// Returns a Boolean value that indicates whether the given window belongs
    /// to one of holzBar's status items.
    static func contains(_ windowID: CGWindowID) -> Bool {
        windowIDs.withLock { $0.values.contains(windowID) }
    }
}
