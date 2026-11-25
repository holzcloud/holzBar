//
//  LiveActivityItem.swift
//  holzBar
//

import Foundation

/// Which menu bar items are system Live Activities, which holzBar never hides, counts, moves,
/// lists in the Shelf or the Layout, or writes to the saved layout.
///
/// From macOS 27.3 the system shows Live Activities (a timer, a recording, music) in the menu
/// bar. This one predicate decides it for every consumer (hiding, counts, moves, Shelf and
/// layout persistence), so no consumer has its own idea of it (D-04). holzBar publishes no
/// Live Activities itself.
///
/// No 27.3 Mac was at hand when this was written (D-16), so the rule is conservative and fails
/// safe: an item that macOS's menu bar process draws and that is not one of the four numbered
/// system items (`SystemItem27`), and an item whose identifier names a Live Activity, stay on
/// the bar and out of every list. That also covers 27.3's app-control indicator, which is
/// never offered for hiding. Probe P4 on a 27.3 Mac fills ``measuredIdentifiers`` and
/// ``measuredHosts`` with what Accessibility really reports, one fixture per measured case.
nonisolated enum LiveActivityItem {
    /// The bundle identifier of the process that draws the system's own menu bar items.
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    /// Lower-case fragments of an identifier that name a Live Activity.
    static let identifierMarkers: [String] = ["liveactivit", "activitykit"]

    /// Identifiers Probe P4 measured on a Live Activity. Empty until a 27.3 Mac has run it.
    static let measuredIdentifiers: Set<String> = []

    /// Bundle identifiers of processes Probe P4 measured as hosts of Live Activities. Empty
    /// until a 27.3 Mac has run it.
    static let measuredHosts: Set<String> = []

    /// Whether an item is a Live Activity (or, by the fail-safe, drawn by the system and unknown).
    ///
    /// - Parameters:
    ///   - ownerBundleID: The owner's bundle identifier.
    ///   - identifier: The item's Accessibility identifier, or empty without one.
    ///   - knownSystemIdentifiers: The identifiers of the system items holzBar manages.
    static func isLiveActivity(
        ownerBundleID: String,
        identifier: String,
        knownSystemIdentifiers: Set<String>
    ) -> Bool {
        if measuredIdentifiers.contains(identifier) || measuredHosts.contains(ownerBundleID) {
            return true
        }
        let lowered = identifier.lowercased()
        if identifierMarkers.contains(where: { lowered.contains($0) }) {
            return true
        }
        return ownerBundleID == menuBarAgentBundleID && !knownSystemIdentifiers.contains(identifier)
    }

    /// The owners that are never concealed: those whose every listed item is a Live Activity,
    /// so concealing the owner would hide nothing else. MenuBarAgent is never listed; it is
    /// never concealed by bundle identifier anyway.
    static func unconcealableOwners(
        items: [(ownerBundleID: String, identifier: String)],
        knownSystemIdentifiers: Set<String>
    ) -> Set<String> {
        var owners = Set<String>()
        var plain = Set<String>()
        for item in items where item.ownerBundleID != menuBarAgentBundleID {
            if isLiveActivity(
                ownerBundleID: item.ownerBundleID,
                identifier: item.identifier,
                knownSystemIdentifiers: knownSystemIdentifiers
            ) {
                owners.insert(item.ownerBundleID)
            } else {
                plain.insert(item.ownerBundleID)
            }
        }
        return owners.subtracting(plain)
    }
}
