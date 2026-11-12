//
//  SettingsSearchModel.swift
//  holzBar
//

import Foundation
import Observation

/// The state of the Settings search. The query lives only in memory: it is never stored in the
/// settings store and never logged. The open disclosures and the open module live here, not in
/// the panes, so a found setting can open them before its pane exists.
@MainActor
@Observable
final class SettingsSearchModel {
    /// What the user typed into the search field.
    var query = ""

    /// The id of the entry the pane should scroll to, set by a found setting and taken by the
    /// pane host that shows it.
    var revealTarget: String?

    /// The id of the entry that is highlighted for a moment after a reveal.
    var highlightedEntry: String?

    /// The ids of the panes' disclosures that are open.
    var openDisclosures: Set<String> = []

    /// The `ModuleDescriptor.id` of the module whose area is open, if any.
    var openModule: String?

    /// Whether the query holds anything but whitespace.
    var isSearching: Bool {
        !query.allSatisfy(\.isWhitespace)
    }

    /// The entries that match the query, best matches first.
    var results: [SettingsEntry] {
        SettingsSearch.results(for: query, in: SettingsCatalog.all)
    }

    /// Ends the search. Nothing else changes, so a pane that is about to be revealed keeps its
    /// target.
    func clear() {
        query = ""
    }
}
