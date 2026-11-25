//
//  NotShownApps.swift
//  holzBar
//

import Foundation

/// The apps macOS does not show in the menu bar, with the reason and the link that fixes it
/// (Phase 97, D-13 and D-18, concept M7).
///
/// There are exactly three reasons, and every one comes from a public signal only: the install
/// location of the app (the rule of `UnnameableApps27`), the overlap heuristic of
/// `HiddenAnyway27`, or a missing bundle identifier. No reason reads another app's permissions,
/// and no row is about Accessibility. Every fix is a link: it reveals a file in Finder or opens
/// the Menu Bar pane of System Settings; holzBar writes no System Settings preference and reads
/// no Control Center preference.
///
/// The names come from other apps, so ``rows(_:)`` cleans them, and callers keep the rows in
/// memory only and never log a name or a path.
nonisolated enum NotShownApps {
    /// Why macOS does not show an app's item. The raw values are only an order; nothing stores them.
    nonisolated enum Reason: Int, CaseIterable, Sendable {
        /// The app runs from outside /Applications and /System, so macOS cannot name its item.
        case notInApplications = 0
        /// A running process without a bundle identifier that owns menu bar items.
        case noAppIdentifier = 1
        /// An app whose item lies hidden under another although it runs from a named place; macOS
        /// may have switched it off in System Settings.
        case mayBeOffInSettings = 2
    }

    /// What the button of a row does.
    nonisolated enum Fix: Sendable {
        /// Reveals the app, or its executable, in Finder.
        case showInFinder
        /// Opens the Menu Bar pane of System Settings.
        case openMenuBarSettings
    }

    /// One app as the model found it.
    nonisolated struct Source: Equatable, Sendable {
        /// The bundle identifier, or `pid:<number>` for a process without one.
        let id: String
        /// The name the system reports, or `nil` when it reports none.
        let name: String?
        /// What stands in when `name` is `nil` or empty: the bundle or executable name.
        let fallbackName: String
        /// The file the fix reveals: the app's bundle, or the executable of a process without one.
        let path: String?
        let reason: Reason
    }

    /// One row of the list.
    nonisolated struct Row: Identifiable, Equatable, Sendable {
        let id: String
        /// The cleaned name.
        let name: String
        let reason: Reason
        let path: String?
        let fix: Fix
    }

    /// The Menu Bar pane of System Settings. A fixed link; the same one the Menu Bar notice uses.
    static let menuBarSettingsURL = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"

    /// The reason of an app the install-location rule does (`true`) or does not name. An app only
    /// `HiddenAnyway27` confirmed has not been named by the rule, so macOS may have switched it off.
    static func reason(unnameableByRule: Bool) -> Reason {
        unnameableByRule ? .notInApplications : .mayBeOffInSettings
    }

    /// What the button of a row with this reason does.
    static func fix(for reason: Reason) -> Fix {
        switch reason {
        case .notInApplications, .noAppIdentifier:
            .showInFinder
        case .mayBeOffInSettings:
            .openMenuBarSettings
        }
    }

    /// The rows for `sources`: one per id (the first source wins), the names cleaned
    /// (``ItemRuleNotices/cleanedName(_:fallback:)``) with the fallback name when the name is
    /// missing or empty, ordered by reason and then by name ignoring case.
    static func rows(_ sources: [Source]) -> [Row] {
        var seen = Set<String>()
        var rows = [Row]()
        for source in sources where seen.insert(source.id).inserted {
            let fallback = ItemRuleNotices.cleanedName(source.fallbackName, fallback: source.id)
            rows.append(Row(
                id: source.id,
                name: ItemRuleNotices.cleanedName(source.name ?? "", fallback: fallback),
                reason: source.reason,
                path: source.path,
                fix: fix(for: source.reason)
            ))
        }
        return rows.sorted { lhs, rhs in
            if lhs.reason != rhs.reason {
                return lhs.reason.rawValue < rhs.reason.rawValue
            }
            let (left, right) = (lhs.name.lowercased(), rhs.name.lowercased())
            if left != right {
                return left < right
            }
            return lhs.id < rhs.id
        }
    }
}
