//
//  OwnStatusItemWindows.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// The window identifiers of holzIce's own status items.
///
/// On macOS 26 every status item window is owned by Control Center, and the
/// application behind an item comes from the menu bar item service. When the
/// service has no answer, holzIce did not recognise even its own section
/// dividers: without them the item cache stayed empty, and the layout settings
/// and the holzIce Bar showed "Loading menu bar items…" forever
/// (jordanbaird/Ice#687, jordanbaird/Ice#710, jordanbaird/Ice#711 and others).
/// holzIce knows its own windows, so it recognises them by these identifiers.
enum OwnStatusItemWindows {
    private static let lock = NSLock()
    private static var windowIDs = [ObjectIdentifier: CGWindowID]()

    /// Records the window of the given owner, replacing its previous one.
    static func set(_ windowNumber: Int?, for owner: AnyObject) {
        lock.withLock {
            // A window number above `UInt32.max` traps a plain conversion
            // (jordanbaird/Ice#989).
            windowIDs[ObjectIdentifier(owner)] = windowNumber.flatMap { CGWindowID(exactly: $0) }
        }
    }

    /// Returns a Boolean value that indicates whether the given window belongs
    /// to one of holzIce's status items.
    static func contains(_ windowID: CGWindowID) -> Bool {
        lock.withLock {
            windowIDs.values.contains(windowID)
        }
    }
}
