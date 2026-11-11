//
//  SettingsCatalog.swift
//  holzBar
//

import Foundation

/// The searchable settings of every pane: static labels only, never user data. The catalog is
/// built once, when it is first read. The app language needs a relaunch to change, so nothing
/// observes it, and nothing here polls or uses a timer.
enum SettingsCatalog {
    /// Every entry of every pane, in sidebar order.
    static let all: [SettingsEntry] = {
        let perPane: [[SettingsEntry]] = [
            LayoutPane.entries,
            ShowingAndHidingPane.entries,
            ShelfPane.entries,
            ProfilesAndHistoryPane.entries,
            AppearancePane.entries,
            AutomationPane.entries,
            ModulesPane.entries,
            GeneralPane.entries,
            HotkeysPane.entries,
            AdvancedPane.entries,
            AboutPane.entries,
        ]
        let entries = Array(perPane.joined())
        assert(isConsistent(perPane, entries: entries), "The settings catalog is inconsistent")
        return entries
    }()

    /// Whether the ids are unique and every per-pane array holds only entries of its own pane.
    /// Called from an `assert`, so release builds do no work beyond the join.
    private static func isConsistent(_ perPane: [[SettingsEntry]], entries: [SettingsEntry]) -> Bool {
        guard perPane.count == SettingsPaneID.allCases.count else { return false }
        guard Set(entries.map(\.id)).count == entries.count else { return false }
        return zip(SettingsPaneID.allCases, perPane).allSatisfy { pane, paneEntries in
            paneEntries.allSatisfy { $0.pane == pane }
        }
    }
}
