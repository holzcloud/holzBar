//
//  PinnedSystemItems.swift
//  holzBar
//

import Foundation

/// The system items that stay visible when holzBar moves items by itself: the clock, the
/// battery, Wi-Fi, Control Center and the sound control.
///
/// A profile, a restored snapshot or a rule that puts one of them into a hidden section
/// leaves it where it is. The user can still move them by hand. Control Center owns these
/// items on macOS 26 and earlier; on macOS 27 holzBar does not move Apple's items at all.
nonisolated enum PinnedSystemItems {
    /// The namespace of the items Control Center draws.
    static let namespace = "com.apple.controlcenter"

    /// The titles of the pinned items, in lower case.
    static let titles: Set<String> = ["clock", "battery", "wifi", "bentobox", "sound"]

    /// Whether the item with this identity key (`namespace:title`) is pinned visible.
    static func isPinned(key: String) -> Bool {
        let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == namespace else {
            return false
        }
        // The canonical title may carry a position suffix (`:2`) for a second item.
        let title = parts[1].split(separator: ":").first.map(String.init) ?? ""
        return titles.contains(title.lowercased())
    }

    /// The wanted sections without the pinned items that would leave the visible section.
    static func keepingPinnedVisible(_ wanted: [String: Int]) -> [String: Int] {
        wanted.filter { key, section in
            section == 0 || !isPinned(key: key)
        }
    }
}
