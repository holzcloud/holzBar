//
//  ItemSpacingAvailability.swift
//  holzBar
//

import Foundation

/// Where the Item spacing setting is offered.
///
/// AppKit reads `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` once per process, and
/// whether macOS 27 honours them at all is probe P7. Until that probe shows it does, the
/// setting is off on macOS 27 and says so (fail safe, D-01 and D-10); Reset stays usable there
/// to clear keys written on macOS 26.
nonisolated enum ItemSpacingAvailability {
    /// Whether macOS 27 honours the spacing keys. Probe P7 decides; flip it when the probe
    /// shows they work.
    ///
    /// Not measured on a Mac yet: probe P7 is deferred to the 1.2.0 beta test (2026-11-22), so nothing
    /// was measured on a Mac. It stays `false`, the fail-safe default.
    static let worksOnMacOS27 = false

    /// Whether the setting takes effect on the given major version of macOS.
    static func isAvailable(macOSMajor: Int) -> Bool {
        macOSMajor < 27 || worksOnMacOS27
    }
}
