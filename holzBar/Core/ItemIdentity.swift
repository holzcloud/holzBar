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
/// Thaw's `canonicalMetricTitle` and `canonicalFirstLineTitle`, and the rule that a launch
/// placeholder is not a title change from Thaw's `FreshVolatileTitleLearner` (GPL-3.0, see
/// NOTICE).
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
    ///
    /// Two more rules come before these:
    /// - A title of several lines is known by its first line (when that is not empty after
    ///   trimming), so "OneDrive - Personal" keeps one key whatever its status line says.
    /// - A Control Center control pinned to the menu bar on macOS 27 loses the instance UUID
    ///   macOS mints each time it places the control (``ControlCenterControl``); its
    ///   identifier is kept as it is.
    static func canonicalTitle(_ title: String) -> String {
        var title = title
        if title.contains(where: \.isNewline),
           let firstLine = title.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first {
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                title = trimmed
            }
        }
        if ControlCenterControl.isPinnedControlTitle(title) {
            return ControlCenterControl.stableIdentity(forTitle: title)
        }
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
    ///
    /// A namespace is not learned either when a title that differs between the reads, in
    /// either direction, is a placeholder (``isPlaceholderTitle(_:)``): a change between
    /// `Item-N` and a real title is the app finishing its launch, not an app whose titles
    /// change (Thaw's `FreshVolatileTitleLearner`).
    ///
    /// The callers pass holzBar's own namespace in `excluding` and must keep doing so:
    /// holzBar's items are tagged by their autosave names, which are identifiers and never
    /// live titles, so learning them would key them by position and break the keys of
    /// profiles and rules.
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
                previousTitles.sorted() != titles.sorted(),
                !changesPlaceholder(from: previousTitles, to: titles)
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
        // A key of this version for a later item without a title: `namespace:<occurrence>`,
        // which starts at 2 and has no leading zero. A raw title such as `0` or `01` is a
        // key of an earlier version and is canonicalised below.
        if title.wholeMatch(of: /[2-9]|[1-9]\d+/) != nil {
            return stored
        }
        // A key of this version: a canonical title (no digits, or an identifier) with an
        // optional `:<occurrence>`.
        if let match = title.wholeMatch(of: /(.*):(\d+)/) {
            let base = String(match.1)
            if canonicalTitle(base) == base,
               !base.contains(where: \.isNumber) || isIdentifier(base) || ControlCenterControl.isPinnedControlTitle(base) {
                return stored
            }
        }
        return baseKey(namespace: namespace, canonicalTitle: canonicalTitle(title))
    }

    /// Returns the stored values keyed by the keys their stored keys match today
    /// (``storedKey(_:titleChangingOwners:)``).
    ///
    /// When several stored keys match one key (a key of an earlier read or version next to
    /// the current one), the value stored under exactly that key wins, else the one whose
    /// stored key sorts first, so the choice is the same on every launch.
    static func storedValues<Value>(_ stored: [String: Value], titleChangingOwners: Set<String>) -> [String: Value] {
        var values = [String: Value]()
        for (storedKey, value) in stored.sorted(by: { $0.key < $1.key }) {
            let key = Self.storedKey(storedKey, titleChangingOwners: titleChangingOwners)
            if storedKey == key || values[key] == nil {
                values[key] = value
            }
        }
        return values
    }

    /// Whether the title is the generic one macOS gives a status item that has no autosave
    /// name or whose app has not finished launching: `Item-` followed by digits.
    static func isPlaceholderTitle(_ title: String) -> Bool {
        title.wholeMatch(of: /Item-[0-9]+/) != nil
    }

    // MARK: Private

    /// Whether a title that is in one of the two reads and not in the other (counted with
    /// repeats) is a placeholder.
    private static func changesPlaceholder(from previous: [String], to current: [String]) -> Bool {
        var counts = [String: Int]()
        for title in previous {
            counts[title, default: 0] += 1
        }
        for title in current {
            counts[title, default: 0] -= 1
        }
        return counts.contains { $0.value != 0 && isPlaceholderTitle($0.key) }
    }

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
