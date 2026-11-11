//
//  SettingsSearch.swift
//  holzBar
//

import Foundation

/// One searchable row of the Settings window: the static texts of the kit, never user data.
nonisolated struct SettingsEntry: Sendable, Hashable, Identifiable {
    let id: String
    let pane: SettingsPaneID
    /// The title of the group that holds the row.
    let group: String
    let label: String
    let info: String?
    /// A module's one-sentence summary.
    let summary: String?
    /// The id of the pane's disclosure that holds the row, if any.
    let disclosure: String?
    /// The id of the module whose open area holds the row, if any.
    let module: String?

    init(
        id: String,
        pane: SettingsPaneID,
        group: String,
        label: String,
        info: String? = nil,
        summary: String? = nil,
        disclosure: String? = nil,
        module: String? = nil
    ) {
        self.id = id
        self.pane = pane
        self.group = group
        self.label = label
        self.info = info
        self.summary = summary
        self.disclosure = disclosure
        self.module = module
    }
}

/// The search over the Settings window's labels, info texts, module summaries and group titles.
/// Pure functions without state or timers. The search reads only the static labels of the kit,
/// never user data, and nothing is logged.
nonisolated enum SettingsSearch {
    /// The text as the search compares it: compatibility-normalised (so full-width and
    /// half-width forms match), then case-, diacritic- and width-insensitive.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The entries that hold every word of the query, in catalogue order, with the entries whose
    /// label holds every word first. A blank query finds nothing.
    static func results(for query: String, in entries: [SettingsEntry]) -> [SettingsEntry] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var byLabel: [SettingsEntry] = []
        var byOther: [SettingsEntry] = []
        for entry in entries {
            let label = fold(entry.label)
            if words.allSatisfy({ label.contains($0) }) {
                byLabel.append(entry)
                continue
            }
            let haystack = [entry.label, entry.info, entry.summary, entry.group]
                .compactMap { $0 }
                .map(fold)
                .joined(separator: "\n")
            if words.allSatisfy({ haystack.contains($0) }) {
                byOther.append(entry)
            }
        }
        return byLabel + byOther
    }

    /// The results grouped by pane in sidebar order, only for panes with a hit.
    static func grouped(_ results: [SettingsEntry]) -> [(pane: SettingsPaneID, entries: [SettingsEntry])] {
        SettingsPaneID.allCases.compactMap { pane in
            let entries = results.filter { $0.pane == pane }
            return entries.isEmpty ? nil : (pane, entries)
        }
    }
}
