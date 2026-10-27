//
//  HolzBarShelfStyle.swift
//  holzBar
//

import Foundation

/// How the holzBar Shelf sits relative to the menu bar.
///
/// The raw values are stored in the user's settings and in exported settings files; a new case
/// goes at the end and no value is ever reused.
nonisolated enum HolzBarShelfStyle: Int, CaseIterable, Identifiable, Sendable {
    /// The Shelf hangs directly below the menu bar, as it always did.
    case attached = 0

    /// The Shelf floats a little below the menu bar, as a bar of its own.
    case floating = 1

    var id: Int { rawValue }

    /// The style stored as `raw`, or `attached` when the number names none: a settings file
    /// or an older or newer holzBar may have written anything.
    static func stored(_ raw: Int) -> HolzBarShelfStyle {
        HolzBarShelfStyle(rawValue: raw) ?? .attached
    }
}
