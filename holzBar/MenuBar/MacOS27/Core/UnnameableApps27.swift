//
//  UnnameableApps27.swift
//  holzBar
//

import Foundation

/// Recognises the applications whose menu bar items MenuBarAgent cannot name on macOS 27.
///
/// Measured on macOS 27.2: MenuBarAgent keys a status item by its owner's bundle identifier
/// only when the owning process runs from `/Applications` or `/System`. The same application
/// run from anywhere else, such as a device management agent installed below `/opt`, is keyed
/// by nothing. An assessment allowlist names bundle identifiers and system item numbers only,
/// so it can never match such an item, and every live assertion, holzBar's included, hides it,
/// even in the visible section. holzBar can only notice this and open the item by releasing
/// the assertions for a moment.
///
/// The rule is the install location of the bundle. ``HiddenAnyway27`` finds the cases the
/// rule misses (an application that runs from a named place but is hidden anyway); the
/// confirmed ones join the answer.
///
/// Processes without a bundle identifier are out of scope: holzBar's reads of the bar skip
/// their items, so they never reach the layout or the holzBar Shelf, and everything built on
/// this rule is keyed by bundle identifier.
nonisolated enum UnnameableApps27 {
    /// An application that owns menu bar items.
    nonisolated struct Owner: Equatable, Sendable {
        let bundleID: String
        /// The path of its bundle, or `nil` when the system reports none.
        let bundlePath: String?
    }

    /// The folders MenuBarAgent names applications from, lowercased with a trailing slash.
    private static let namedPrefixes = ["/applications/", "/system/"]

    /// Whether MenuBarAgent cannot name the application with the given bundle.
    ///
    /// The path is standardised first (`..` and `.` resolved) and compared without regard to
    /// case, and a prefix must end at a folder boundary, so `/Applications.old` is not
    /// `/Applications`. An application with no bundle path or no bundle identifier cannot be
    /// named either; no caller asks about a process without a bundle identifier.
    static func isUnnameable(bundleID: String?, bundlePath: String?) -> Bool {
        guard bundleID != nil, let bundlePath else {
            return true
        }
        let path = URL(fileURLWithPath: bundlePath).standardizedFileURL.path.lowercased()
        return !namedPrefixes.contains { path.hasPrefix($0) }
    }

    /// The bundle identifiers to report: those the rule names unnameable, and those in
    /// `confirmed`, in the order first seen and without duplicates.
    static func owners(_ owners: [Owner], confirmed: Set<String>) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for owner in owners where seen.insert(owner.bundleID).inserted {
            if isUnnameable(bundleID: owner.bundleID, bundlePath: owner.bundlePath) || confirmed.contains(owner.bundleID) {
                result.append(owner.bundleID)
            }
        }
        return result
    }
}
