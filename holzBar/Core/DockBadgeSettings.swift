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

/// What a Dock badges item shows while its count is zero (Dock badges, D-02, D-13): one setting
/// for every item.
///
/// The raw values are stored and exported (`DockBadgeZeroMode`); new ones are only appended.
nonisolated enum DockBadgeZeroMode: Int, CaseIterable, Sendable {
    /// The item stays in place with its icon at half strength and no bubble, so the bar does not
    /// jump. The default.
    case dim = 0
    /// The item takes no width until the count is above zero, and keeps its place and section.
    case hide = 1

    /// The mode a stored raw value stands for: Dim when nothing is stored or the value is none of
    /// the known ones (the defaults can hold anything).
    static func stored(_ raw: Int?) -> DockBadgeZeroMode {
        raw.flatMap(DockBadgeZeroMode.init(rawValue:)) ?? .dim
    }
}

/// One group of Dock badges apps: a menu bar item that shows the sum of its apps' counts and opens
/// a menu of them (Dock badges, D-06).
///
/// The fields are stored and exported (`DockBadgeGroups`); new ones are only appended. The name is
/// the user's own and stays in the user's settings and in memory.
nonisolated struct DockBadgeGroup: Codable, Equatable, Identifiable, Sendable {
    /// What names the group's menu bar item (``DockBadgeItemName/group(_:)``); it never changes.
    var id: UUID
    /// What the user called the group.
    var name: String
    /// The bundle identifiers of the group's apps, in the order they joined.
    var apps: [String]
}

/// The stored list of groups: decoded element by element, validated, capped and encoded again.
///
/// The list comes from the defaults, an imported settings file or any process of the user, so
/// nothing in it is trusted (T-98-27): at most ``maximumCount`` groups, each with a unique
/// identifier and a name of one line and at most ``maximumNameLength`` characters, bundle
/// identifiers that are valid and unique, and every app in one group only (the first that names
/// it keeps it).
nonisolated enum DockBadgeGroupList {
    /// The most groups.
    static let maximumCount = 12

    /// The longest name of a group, in characters.
    static let maximumNameLength = 64

    /// The most bytes of a list that is read or written.
    static let maximumDataSize = 65_536

    /// A name with its white space trimmed, line breaks and runs of white space made one space and
    /// no more than ``maximumNameLength`` characters; `nil` when nothing is left.
    static func cleanedName(_ name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace)
        let cleaned = String(words.joined(separator: " ").prefix(maximumNameLength))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The groups that may be kept: a name that is empty or an identifier seen before drops the
    /// group, names are cleaned, apps are sanitized and kept in the first group that names them,
    /// at most ``maximumCount`` groups.
    static func validated(_ groups: [DockBadgeGroup]) -> [DockBadgeGroup] {
        var seen = Set<UUID>()
        var claimed = Set<String>()
        var kept = [DockBadgeGroup]()
        for group in groups {
            guard let name = cleanedName(group.name), seen.insert(group.id).inserted else {
                continue
            }
            let apps = DockBadgeApps.sanitized(group.apps).filter { claimed.insert($0).inserted }
            kept.append(DockBadgeGroup(id: group.id, name: name, apps: apps))
            if kept.count == maximumCount {
                break
            }
        }
        return kept
    }

    /// The groups of a stored list, validated. Data that is too large or is not a JSON array gives
    /// an empty list.
    static func decode(_ data: Data) -> [DockBadgeGroup] {
        list(from: data) ?? []
    }

    /// The JSON to store, with sorted keys, or `nil` when it would be over ``maximumDataSize``.
    static func encode(_ groups: [DockBadgeGroup]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(groups), data.count <= maximumDataSize else {
            return nil
        }
        return data
    }

    /// An imported list as it may be applied: decoded, validated and encoded again, so that an
    /// unknown field, a thirteenth group or an app in two groups never reaches the defaults. `nil`
    /// when the data is too large or is not a JSON array.
    static func normalized(_ data: Data) -> Data? {
        guard let groups = list(from: data) else {
            return nil
        }
        return encode(groups)
    }

    /// The list after an app joins a group, or leaves every group (`groupID` is `nil`). Joining
    /// takes the app out of the group it was in and puts it at the end of the new group's apps. An
    /// unknown group and an invalid bundle identifier change nothing.
    static func assigning(_ bundleID: String, to groupID: UUID?, in groups: [DockBadgeGroup]) -> [DockBadgeGroup] {
        var result = groups
        if let groupID {
            guard SharedProfile.isValidBundleIdentifier(bundleID), groups.contains(where: { $0.id == groupID }) else {
                return groups
            }
            if groups.first(where: { $0.id == groupID })?.apps.contains(bundleID) == true,
                !groups.contains(where: { $0.id != groupID && $0.apps.contains(bundleID) }) {
                return groups
            }
        }
        for index in result.indices {
            result[index].apps.removeAll { $0 == bundleID }
        }
        if let groupID, let index = result.firstIndex(where: { $0.id == groupID }) {
            result[index].apps.append(bundleID)
        }
        return result
    }

    /// The list with the app taken out of every group.
    static func removingApp(_ bundleID: String, from groups: [DockBadgeGroup]) -> [DockBadgeGroup] {
        assigning(bundleID, to: nil, in: groups)
    }

    /// The list with a deleted group put back at its former index (clamped to the list as it is
    /// now), without the apps another group has taken since. Nothing changes when a group with its
    /// identifier is there or the list is full.
    static func reinserting(_ group: DockBadgeGroup, at index: Int, into groups: [DockBadgeGroup]) -> [DockBadgeGroup] {
        guard groups.count < maximumCount, !groups.contains(where: { $0.id == group.id }) else {
            return groups
        }
        let taken = Set(groups.flatMap(\.apps))
        var restored = group
        restored.apps = group.apps.filter { !taken.contains($0) }
        var result = groups
        result.insert(restored, at: min(max(index, 0), result.count))
        return result
    }

    private static func list(from data: Data) -> [DockBadgeGroup]? {
        guard data.count <= maximumDataSize,
            let elements = try? JSONDecoder().decode([LossyGroup].self, from: data)
        else {
            return nil
        }
        return validated(elements.compactMap(\.value))
    }
}

/// One element of a stored list that is skipped when it cannot be decoded, instead of making the
/// whole list unreadable.
nonisolated private struct LossyGroup: Decodable {
    let value: DockBadgeGroup?

    init(from decoder: any Decoder) {
        value = try? DockBadgeGroup(from: decoder)
    }
}

/// One menu bar item of Dock badges: an app's, or a group's.
nonisolated enum DockBadgeItemKind: Equatable, Sendable {
    /// The item of one chosen app that is in no group, by bundle identifier.
    case app(String)
    /// The item of a group that has at least one chosen app, by the group's identifier.
    case group(UUID)

    /// The autosave name of the item.
    var autosaveName: String {
        switch self {
        case .app(let bundleID): DockBadgeItemName.app(bundleID)
        case .group(let id): DockBadgeItemName.group(id)
        }
    }
}

/// Which items the choice of apps and the groups make (Dock badges, D-06): a chosen app that is
/// in a group shows only in its group's item.
nonisolated enum DockBadgeItemList {
    /// The items to show: the chosen apps that no group holds, in the order chosen, then every
    /// group that holds at least one chosen app, in the order of the groups. Never an app twice
    /// (an app in two groups of a list that was not normalized belongs to the first), and never a
    /// group without a chosen app.
    static func items(apps: [String], groups: [DockBadgeGroup]) -> [DockBadgeItemKind] {
        let grouped = Set(groups.flatMap(\.apps))
        var seen = Set<String>()
        var items = [DockBadgeItemKind]()
        for bundleID in apps where !grouped.contains(bundleID) && seen.insert(bundleID).inserted {
            items.append(.app(bundleID))
        }
        for group in groups where !members(of: group, in: groups, apps: apps).isEmpty {
            items.append(.group(group.id))
        }
        return items
    }

    /// The chosen apps that are in the group, in the group's order, without those an earlier group
    /// holds as well.
    static func members(of group: DockBadgeGroup, in groups: [DockBadgeGroup], apps: [String]) -> [String] {
        let chosen = Set(apps)
        var claimed = Set<String>()
        for other in groups {
            if other.id == group.id {
                break
            }
            claimed.formUnion(other.apps)
        }
        var seen = Set<String>()
        return group.apps.filter { chosen.contains($0) && !claimed.contains($0) && seen.insert($0).inserted }
    }
}

/// The autosave names of the status items that Dock badges adds to the menu bar.
///
/// An item's name is its identity for macOS (its place in the bar) and for holzBar (its section
/// and its label), so it is built here only, from the app's bundle identifier or the group's
/// identifier. It differs from a widget's, a replacement's and a stand-in's name by its prefix. A
/// bundle identifier or a group identifier is checked when a name is taken apart, because a name
/// can come from stored defaults.
nonisolated enum DockBadgeItemName {
    /// The start of every Dock badges item's autosave name.
    static let prefix = "holzBar.DockBadge."

    /// The start of the name of an app's item.
    private static let appPrefix = prefix + "App."

    /// The start of the name of a group's item.
    private static let groupPrefix = prefix + "Group."

    /// The autosave name of the item that shows an app's badge.
    static func app(_ bundleID: String) -> String {
        appPrefix + bundleID
    }

    /// The autosave name of the item of a group.
    static func group(_ id: UUID) -> String {
        groupPrefix + id.uuidString
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

    /// The identifier in a group item's name, or `nil` for any other name. Only the canonical
    /// form counts (upper-case, as ``group(_:)`` writes it), so a group has one name.
    static func groupID(fromAutosaveName name: String) -> UUID? {
        guard name.hasPrefix(groupPrefix) else {
            return nil
        }
        let text = String(name.dropFirst(groupPrefix.count))
        guard let id = UUID(uuidString: text), id.uuidString == text else {
            return nil
        }
        return id
    }

    /// Whether a name is the autosave name of an item of Dock badges: its prefix alone, an empty
    /// or an invalid identifier does not make one.
    static func isAutosaveName(_ name: String) -> Bool {
        bundleID(fromAutosaveName: name) != nil || groupID(fromAutosaveName: name) != nil
    }
}
