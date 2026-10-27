//
//  ShelfAlwaysHiddenFold.swift
//  holzBar
//

import Foundation

/// How the holzBar Shelf treats the fold tile that holds the always-hidden items.
///
/// The raw values are stored in the user's settings and in exported settings files; a new case
/// goes at the end and no value is ever reused.
nonisolated enum ShelfAlwaysHiddenFold: Int, CaseIterable, Identifiable, Sendable {
    /// The Shelf opens with the fold closed, every time.
    case foldedEachTime = 0
    /// The Shelf opens with the fold as the user left it.
    case remembered = 1

    var id: Int { rawValue }

    /// The choice stored as `raw`, or `foldedEachTime` when the number names none: a settings
    /// file or an older or newer holzBar may have written anything.
    static func stored(_ raw: Int) -> ShelfAlwaysHiddenFold {
        ShelfAlwaysHiddenFold(rawValue: raw) ?? .foldedEachTime
    }

    /// Whether the fold is open when the Shelf opens.
    ///
    /// - Parameters:
    ///   - wasLeftOpen: Whether the user left the fold open the last time.
    func opensFold(wasLeftOpen: Bool) -> Bool {
        switch self {
        case .foldedEachTime: false
        case .remembered: wasLeftOpen
        }
    }
}
