//
//  MenuBarSpacers.swift
//  holzBar
//

import AppKit
import Observation

/// Empty menu bar items that make space between others (jordanbaird/Ice#91).
///
/// Each spacer is an empty status item of a fixed width. It can be dragged
/// anywhere with ⌘ Command, like any other item, and macOS remembers where.
@MainActor
@Observable
final class MenuBarSpacers {
    /// The most spacers there can be.
    static let maximumCount = 10

    /// The number of spacers.
    var count = 0 {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(count, forKey: .spacerCount)
            }
            update()
        }
    }

    /// The width of each spacer, in points.
    var width: Double = 16 {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(width, forKey: .spacerWidth)
            }
            update()
        }
    }

    @ObservationIgnored private var statusItems = [NSStatusItem]()

    /// A Boolean value that indicates whether ``performSetup()`` is assigning the stored
    /// values. While it is, nothing is saved: out-of-range values are clamped in memory
    /// and the stored ones stay as they were (analysis §4.9 item 2).
    @ObservationIgnored private var isLoadingStoredValues = false

    func performSetup() {
        isLoadingStoredValues = true
        defer {
            isLoadingStoredValues = false
        }
        if let stored = Defaults.object(forKey: .spacerWidth) as? Double {
            // Kept in the slider's range; the pane shows it as an `Int`.
            width = Defaults.Key.spacerWidth.clamped(stored, fallback: width)
        }
        if let stored = Defaults.object(forKey: .spacerCount) as? Int {
            count = min(max(stored, 0), Self.maximumCount)
        }
        update()
    }

    private func update() {
        while statusItems.count > count, let statusItem = statusItems.popLast() {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        while statusItems.count < count {
            let statusItem = NSStatusBar.system.statusItem(withLength: width)
            statusItem.autosaveName = "holzBar.Spacer.\(statusItems.count + 1)"
            statusItem.button?.title = ""
            statusItem.button?.toolTip = "Spacer"
            statusItems.append(statusItem)
        }
        for statusItem in statusItems {
            statusItem.length = width
        }
    }
}
