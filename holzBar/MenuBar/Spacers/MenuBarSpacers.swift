//
//  MenuBarSpacers.swift
//  holzBar
//

import AppKit
import Combine

/// Empty menu bar items that make space between others (jordanbaird/Ice#91).
///
/// Each spacer is an empty status item of a fixed width. It can be dragged
/// anywhere with ⌘ Command, like any other item, and macOS remembers where.
@MainActor
final class MenuBarSpacers: ObservableObject {
    /// The most spacers there can be.
    static let maximumCount = 10

    /// The number of spacers.
    @Published var count = 0 {
        didSet {
            Defaults.set(count, forKey: .spacerCount)
            update()
        }
    }

    /// The width of each spacer, in points.
    @Published var width: Double = 16 {
        didSet {
            Defaults.set(width, forKey: .spacerWidth)
            update()
        }
    }

    private var statusItems = [NSStatusItem]()

    func performSetup() {
        if let stored = Defaults.object(forKey: .spacerWidth) as? Double {
            width = stored
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
