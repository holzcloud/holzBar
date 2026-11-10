//
//  SyntheticWindowID27.swift
//  holzBar
//

import Foundation

/// Identifiers for menu bar items that have no WindowServer window on macOS 27.
///
/// holzBar's item model is keyed by window identifier. Real identifiers are small
/// counters, so synthetic ones set the top bit to stay out of their way.
nonisolated enum SyntheticWindowID27 {
    static let flag: UInt32 = 0x8000_0000

    /// A stable identifier for an item, derived from its owner, its identifier and its
    /// occurrence among the owner's items with that identifier.
    ///
    /// The occurrence replaces the Accessibility child index the identifier used to hash: the
    /// index of every system item moved when macOS's overflow button ("«") came or went, so
    /// they changed identity (27-L2, D-17). The number is not dropped, because some apps give
    /// several items the same identifier, which would then collide. Synthetic identifiers live
    /// only while holzBar runs; no stored setting holds one, so changing how they are made
    /// loses nothing.
    static func make(bundleID: String, identifier: String, occurrence: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in "\(bundleID)\u{1F}\(identifier)\u{1F}\(occurrence)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return flag | (hash & ~flag)
    }

    /// For each identifier in an owner's item list, how many items before it have the same one.
    ///
    /// `["a", "b", "a"]` gives `[0, 0, 1]`: an item's occurrence changes only when an item with
    /// the same identifier comes or goes before it, not when any other item does.
    static func occurrences(identifiers: [String]) -> [Int] {
        var seen = [String: Int]()
        return identifiers.map { identifier in
            defer {
                seen[identifier, default: 0] += 1
            }
            return seen[identifier, default: 0]
        }
    }

    static func isSynthetic(_ windowID: UInt32) -> Bool {
        windowID & flag != 0
    }
}
