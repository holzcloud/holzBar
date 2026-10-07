//
//  LayoutSeedRepair.swift
//  holzBar
//

import Foundation

/// The decision of the one-time repair of the "macOS 27 layout seeded" flag.
///
/// holzBar 0.0.6-beta1 merged settings between Macs with a logical OR, so a Mac before
/// macOS 27 could receive `MacOS27LayoutSeeded` from a macOS 27 Mac while its own
/// `MacOS27Layout` was still empty. Left alone, that Mac would skip seeding the layout
/// after an upgrade to macOS 27 (analysis §4.9 item 9). The flag is local state, so
/// clearing it needs no consent from other Macs.
nonisolated enum LayoutSeedRepair {
    /// Whether the seeded flag is an artifact that must be cleared.
    ///
    /// - Parameters:
    ///   - isMacOS27: Whether this Mac runs macOS 27 or later.
    ///   - seeded: Whether `MacOS27LayoutSeeded` is set.
    ///   - layoutIsEmpty: Whether `MacOS27Layout` is missing or holds no entry.
    static func shouldClearSeededFlag(isMacOS27: Bool, seeded: Bool, layoutIsEmpty: Bool) -> Bool {
        !isMacOS27 && seeded && layoutIsEmpty
    }
}
