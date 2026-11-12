//
//  LayoutList.swift
//  holzBar
//

import Foundation

/// The filter of Layout's list and bars: by the item's name and its app's name (D-09).
nonisolated enum LayoutListFilter {
    /// Whether a row passes the filter. An empty query lets every row through; the match
    /// ignores case and diacritics, and an item without an app matches by its name only.
    static func matches(query: String, itemName: String, appName: String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if itemName.range(of: query, options: options) != nil {
            return true
        }
        return appName?.range(of: query, options: options) != nil
    }
}
