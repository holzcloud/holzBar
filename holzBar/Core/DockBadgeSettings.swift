//
//  DockBadgeSettings.swift
//  holzBar
//

import Foundation

/// One application as the Dock lists it: the bundle identifier that names it everywhere else, the
/// name the Dock shows and whether it runs.
nonisolated struct DockAppItem: Equatable, Sendable {
    let bundleID: String
    let name: String
    let isRunning: Bool
}

/// One row of the Dock badges settings: an app the user can switch on, or a chosen app that has
/// left the Dock and keeps its row so that it can be switched off.
nonisolated struct DockAppRow: Equatable, Identifiable, Sendable {
    let bundleID: String
    let name: String
    let isChosen: Bool
    let isInDock: Bool

    var id: String { bundleID }
}

/// The choice of apps whose Dock badge shows in the menu bar, and the rows the settings list
/// (Dock badges, D-05).
///
/// The choice is stored as bundle identifiers only (`DockBadgeApps`), in the order chosen. A
/// stored list comes from the defaults or from an imported settings file and can be anything, so
/// ``sanitized(_:)`` keeps only valid, unique identifiers, at most ``maximumCount``. The names
/// come from another process, so ``rows(chosen:dock:nameOf:)`` cleans them; callers keep the rows
/// in memory only and never log a name.
nonisolated enum DockBadgeApps {
    /// The most apps that can be chosen.
    static let maximumCount = 64

    /// The longest name a row shows, in characters.
    static let maximumNameLength = 80

    /// The identifiers that are valid bundle identifiers, without repeats (the first stays), at
    /// most ``maximumCount``.
    static func sanitized(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        var kept = [String]()
        for bundleID in stored where SharedProfile.isValidBundleIdentifier(bundleID) {
            guard seen.insert(bundleID).inserted else {
                continue
            }
            kept.append(bundleID)
            if kept.count == maximumCount {
                break
            }
        }
        return kept
    }

    /// The rows of the settings: the Dock's apps in the Dock's order, one row per bundle
    /// identifier (the first entry gives the name when the Dock lists an app twice), then every
    /// chosen app that is not in the Dock, in the order chosen, with ``DockAppRow/isInDock`` false.
    ///
    /// - Parameters:
    ///   - chosen: The stored choice.
    ///   - dock: The apps the Dock lists now.
    ///   - nameOf: The name of an app that is not in the Dock, when the caller can find one; the
    ///     bundle identifier stands in otherwise.
    static func rows(
        chosen: [String],
        dock: [DockAppItem],
        nameOf: (String) -> String? = { _ in nil }
    ) -> [DockAppRow] {
        let chosenSet = Set(chosen)
        var seen = Set<String>()
        var rows = [DockAppRow]()
        for item in dock where seen.insert(item.bundleID).inserted {
            rows.append(DockAppRow(
                bundleID: item.bundleID,
                name: cleanedName(item.name, fallback: item.bundleID),
                isChosen: chosenSet.contains(item.bundleID),
                isInDock: true
            ))
        }
        for bundleID in chosen where seen.insert(bundleID).inserted {
            rows.append(DockAppRow(
                bundleID: bundleID,
                name: cleanedName(nameOf(bundleID) ?? "", fallback: bundleID),
                isChosen: true,
                isInDock: false
            ))
        }
        return rows
    }

    /// The choice after one app is switched on or off. A newly chosen app goes to the end; a
    /// switched-off one leaves and the others keep their order. An invalid identifier and a
    /// choice past ``maximumCount`` change nothing.
    static func setting(_ bundleID: String, chosen: Bool, in stored: [String]) -> [String] {
        if chosen {
            guard !stored.contains(bundleID),
                SharedProfile.isValidBundleIdentifier(bundleID),
                stored.count < maximumCount
            else {
                return stored
            }
            return stored + [bundleID]
        }
        return stored.filter { $0 != bundleID }
    }

    /// A name with its white space trimmed, line breaks and runs of white space made one space
    /// and no more than ``maximumNameLength`` characters; the fallback when nothing is left.
    private static func cleanedName(_ name: String, fallback: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let cleaned = String(words.joined(separator: " ").prefix(maximumNameLength))
        return cleaned.isEmpty ? fallback : cleaned
    }
}

/// The autosave names of the status items that Dock badges adds to the menu bar.
///
/// An item's name is its identity for macOS (its place in the bar) and for holzBar (its section
/// and its label), so it is built here only, from the app's bundle identifier. It differs from a
/// widget's, a replacement's and a stand-in's name by its prefix. A bundle identifier is checked
/// when a name is taken apart, because a name can come from stored defaults.
nonisolated enum DockBadgeItemName {
    /// The start of every Dock badges item's autosave name.
    static let prefix = "holzBar.DockBadge."

    /// The start of the name of an app's item.
    private static let appPrefix = prefix + "App."

    /// The autosave name of the item that shows an app's badge.
    static func app(_ bundleID: String) -> String {
        appPrefix + bundleID
    }

    /// The bundle identifier in an app item's name, or `nil` for any other name and for an empty
    /// or invalid identifier.
    static func bundleID(fromAutosaveName name: String) -> String? {
        guard name.hasPrefix(appPrefix) else {
            return nil
        }
        let bundleID = String(name.dropFirst(appPrefix.count))
        return SharedProfile.isValidBundleIdentifier(bundleID) ? bundleID : nil
    }

    /// Whether a name belongs to an item of Dock badges.
    static func isAutosaveName(_ name: String) -> Bool {
        name.hasPrefix(prefix)
    }
}
