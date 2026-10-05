//
//  ItemIdentity.swift
//  holzBar
//

import Foundation

/// The identity holzBar stores for a menu bar item: a key that stays the same when the
/// item's title changes.
///
/// An item is known by its namespace (the bundle identifier of its app) and its title. Many
/// apps put a live value in the title — a count of unread mail, the date, a CPU load — so a
/// key built from the raw title changed with every update: the item counted as new and was
/// moved into the new-items section, and profiles and groups lost it. The key is built from
/// the title with its numbers replaced (``canonicalTitle(_:)``); apps whose titles change
/// beyond that are learned (``learnTitleChangingOwners(previous:current:excluding:)``) and
/// their items are keyed by their position among the app's items. Several items of one app
/// with the same canonical title are told apart by a number.
///
/// Keys stored by earlier versions (`namespace:title`) still match through
/// ``storedKey(_:titleChangingOwners:)``. The canonical form of a title is adapted from
/// Thaw's `canonicalMetricTitle` (GPL-3.0, see NOTICE).
nonisolated enum ItemIdentity {
    /// One item, as read from the bar: its namespace and its title.
    typealias Item = (namespace: String, title: String)

    /// The title with its live values replaced, so "Mail 3" and "Mail 12" are one title.
    ///
    /// Numbers become `#` and byte units are normalised ("CPU 12%" becomes "CPU #%",
    /// "Network 3 KB/s" becomes "Network # B/s"). Titles that are identifiers, such as
    /// `Item-0` or `com.apple.menuextra.clock` (a letter followed by letters, digits, dots,
    /// hyphens and underscores only), are kept as they are: their digits tell the items of
    /// one app apart and never change.
    static func canonicalTitle(_ title: String) -> String {
        if isIdentifier(title) {
            return title
        }
        return title
            .replacing(/[-+]?\d+(?:[.,]\d+)?/, with: "#")
            .replacing(/#\s*[KMGTPE]?[Bb]\/s/, with: "# B/s")
            .replacing(/#\s*[KMGTPE]?[Bb]/, with: "# B")
    }

    /// Returns the namespaces whose item titles changed beyond their numbers between two
    /// reads of the bar.
    ///
    /// A namespace is learned when it has the same, non-zero number of items in both reads
    /// and the canonical titles of those items differ. Namespaces in `excluding` (holzBar's
    /// own) and UUID namespaces (system items whose namespace changes on every launch) are
    /// never learned.
    static func learnTitleChangingOwners(previous: [Item], current: [Item], excluding: Set<String>) -> Set<String> {
        let previousTitles = canonicalTitlesByNamespace(previous)
        let currentTitles = canonicalTitlesByNamespace(current)
        var learned = Set<String>()
        for (namespace, titles) in currentTitles {
            guard
                !excluding.contains(namespace),
                UUID(uuidString: namespace) == nil,
                let previousTitles = previousTitles[namespace],
                !titles.isEmpty,
                previousTitles.count == titles.count,
                previousTitles.sorted() != titles.sorted()
            else {
                continue
            }
            learned.insert(namespace)
        }
        return learned
    }

    /// Returns the key of each item, in the order of `items` (the bar's order, left to right).
    ///
    /// - The items of a namespace in `titleChangingOwners` are keyed by their position among
    ///   that namespace's items: `namespace:#1`, `namespace:#2`, …
    /// - Every other item is keyed `namespace:canonical title`; a second item of the same
    ///   namespace with the same canonical title gets `:2`, a third `:3`, and so on.
    static func keys(for items: [Item], titleChangingOwners: Set<String>) -> [String] {
        var positions = [String: Int]()
        var occurrences = [String: Int]()
        return items.map { item in
            if titleChangingOwners.contains(item.namespace) {
                let position = positions[item.namespace, default: 0] + 1
                positions[item.namespace] = position
                return "\(item.namespace):#\(position)"
            }
            let base = baseKey(namespace: item.namespace, canonicalTitle: canonicalTitle(item.title))
            let occurrence = occurrences[base, default: 0] + 1
            occurrences[base] = occurrence
            return occurrence == 1 ? base : "\(base):\(occurrence)"
        }
    }

    /// Returns the key a stored key matches today.
    ///
    /// Earlier versions stored `namespace:raw title`; such a key is canonicalised, and for a
    /// namespace in `titleChangingOwners` it matches the app's first item. Keys this version
    /// stored are returned unchanged, including `namespace:2`, `namespace:3`, … of the later
    /// items of an app whose items have no title.
    static func storedKey(_ stored: String, titleChangingOwners: Set<String>) -> String {
        guard let separator = stored.firstIndex(of: ":") else {
            // A namespace without a title.
            return titleChangingOwners.contains(stored) ? "\(stored):#1" : stored
        }
        let namespace = String(stored[..<separator])
        let title = String(stored[stored.index(after: separator)...])
        if titleChangingOwners.contains(namespace) {
            if title.wholeMatch(of: /#\d+/) != nil {
                return stored
            }
            return "\(namespace):#1"
        }
        // A key of this version for a later item without a title: `namespace:<occurrence>`.
        if title.wholeMatch(of: /\d+/) != nil {
            return stored
        }
        // A key of this version: a canonical title (no digits, or an identifier) with an
        // optional `:<occurrence>`.
        if let match = title.wholeMatch(of: /(.*):(\d+)/) {
            let base = String(match.1)
            if canonicalTitle(base) == base, !base.contains(where: \.isNumber) || isIdentifier(base) {
                return stored
            }
        }
        return baseKey(namespace: namespace, canonicalTitle: canonicalTitle(title))
    }

    // MARK: Private

    /// Whether the title is an identifier rather than text: a letter followed by letters,
    /// digits, dots, hyphens and underscores only.
    private static func isIdentifier(_ title: String) -> Bool {
        title.wholeMatch(of: /[A-Za-z][A-Za-z0-9._\-]*/) != nil
    }

    /// The key of an item without an occurrence number.
    private static func baseKey(namespace: String, canonicalTitle: String) -> String {
        canonicalTitle.isEmpty ? namespace : "\(namespace):\(canonicalTitle)"
    }

    /// The canonical titles of each namespace's items.
    private static func canonicalTitlesByNamespace(_ items: [Item]) -> [String: [String]] {
        items.reduce(into: [String: [String]]()) { result, item in
            result[item.namespace, default: []].append(canonicalTitle(item.title))
        }
    }
}
