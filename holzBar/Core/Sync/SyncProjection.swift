//
//  SyncProjection.swift
//  holzBar
//

import Foundation

/// Maps between holzBar's defaults and the units the sync engine moves.
///
/// The engine only ever sees units (``SyncUnitKey`` and ``SyncValue``), never raw defaults.
/// ``snapshot(defaults:table:generation:)`` reads the defaults into units,
/// ``defaultsWrites(applying:to:table:)`` turns units back into the smallest set of defaults
/// writes, and neither touches a key that has no synced class (``SyncUnitTable/keyClass(_:)``).
///
/// Anything can write holzBar's preferences, and a value from another Mac is a value from
/// outside the app, so every value is checked on its way in (per value, never per
/// dictionary: one bad hotkey does not cost the other hotkeys).
nonisolated enum SyncProjection {
    /// What a present stored value that is not a property list holzBar can move (such as a
    /// number that does not fit) projects to. No unit accepts it, so the engine marks the
    /// unit local-only as invalid instead of reading an absent value.
    static let unrepresentable = SyncValue.dictionary(["unrepresentable": .bool(true)])

    // MARK: Snapshot

    /// The units the defaults hold, with the present values only, normalized.
    ///
    /// A present value that is not valid for its unit is still returned (unnormalized where
    /// it cannot be normalized), so the engine can keep it local-only; an absent value is not
    /// returned. The families that only macOS 27 authors (`l27`, `prof`) are returned only
    /// for ``SyncGeneration/g27``.
    static func snapshot(defaults: [String: Any], table: SyncUnitTable, generation: SyncGeneration) -> [SyncUnitKey: SyncValue] {
        var units: [SyncUnitKey: SyncValue] = [:]
        var icon: [String: SyncValue] = [:]
        for key in SyncUnitTable.syncedKeys {
            guard let stored = defaults[key.rawValue] else {
                continue
            }
            switch SyncUnitTable.keyClass(key) {
            case .whole(let unit):
                units[.whole(unit)] = wholeValue(key, stored, table: table)
            case .holzBarIconPart:
                let field = key == .holzBarIcon ? SyncNormalizers.iconField : SyncNormalizers.templateField
                icon[field] = SyncValue(propertyList: stored) ?? unrepresentable
            case .split(let family):
                for (item, value) in splitItems(of: key, stored) where table.descriptor(for: .split(family: family, item: item)) != nil {
                    units[.split(family: family, item: item)] = value
                }
            case .layout27:
                guard generation == .g27 else {
                    continue
                }
                for (item, value) in layoutItems(stored) where table.descriptor(for: .split(family: SyncUnitTable.layout27Family, item: item)) != nil {
                    units[.split(family: SyncUnitTable.layout27Family, item: item)] = value
                }
            case .profiles:
                guard generation == .g27 else {
                    continue
                }
                for (item, value) in profileItems(stored) {
                    units[.split(family: SyncUnitTable.profilesFamily, item: item)] = value
                }
            case .knownApplications27, .local:
                continue
            }
        }
        if !icon.isEmpty {
            let value = SyncValue.dictionary(icon)
            units[.whole(SyncUnitTable.holzBarIconUnit)] = table.normalizers.holzBarIcon(value) ?? value
        }
        return units
    }

    /// The value of a unit on this Mac: the snapshot's, or for an application of `l27` that
    /// has no stored section, visible (`0`), which is a value and never an absence (D-04).
    static func localValue(_ key: SyncUnitKey, in snapshot: [SyncUnitKey: SyncValue], table: SyncUnitTable) -> SyncValue? {
        if let value = snapshot[key] {
            return value
        }
        if case .split(let family, _) = key, family == SyncUnitTable.layout27Family, table.descriptor(for: key) != nil {
            return .integer(0)
        }
        return nil
    }

    /// The applications a macOS 27 Mac knows, for the set `known27`.
    static func knownApplications(in defaults: [String: Any]) -> [String] {
        let stored = defaults[Defaults.Key.knownApplications27.rawValue] as? [String] ?? []
        return Array(Set(stored.filter(SyncUnitTable.isItemKey))).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func wholeValue(_ key: Defaults.Key, _ stored: Any, table: SyncUnitTable) -> SyncValue {
        guard let value = SyncValue(propertyList: stored) else {
            return unrepresentable
        }
        switch key {
        case .menuBarAppearanceConfigurationV2:
            return table.normalizers.appearance(value) ?? value
        case .itemGroups:
            return table.normalizers.itemGroups(value) ?? value
        default:
            return normalizedNumber(value, rule: key.numberRule)
        }
    }

    /// A number kept in the range of its setting, as the models keep it; an integer stays an
    /// integer. A value the rule refuses stays as it is and fails validation.
    private static func normalizedNumber(_ value: SyncValue, rule: SettingsSchema.NumberRule?) -> SyncValue {
        guard let rule else {
            return value
        }
        let number: Double
        switch value {
        case .integer(let integer):
            number = Double(integer)
        case .real(let real):
            number = real
        default:
            return value
        }
        guard let sanitized = rule.sanitized(NSNumber(value: number)) else {
            return value
        }
        let clamped = sanitized.doubleValue
        if clamped == number {
            return value
        }
        if case .integer = value, clamped.rounded() == clamped {
            return .integer(Int64(clamped))
        }
        return .real(clamped)
    }

    private static func splitItems(of key: Defaults.Key, _ stored: Any) -> [(item: String, value: SyncValue)] {
        if key == .revealOnChangeItems {
            guard let elements = stored as? [Any] else {
                return []
            }
            let marked = Set(elements.compactMap { $0 as? String }.filter(SyncUnitTable.isItemKey))
            return marked.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { ($0, SyncValue.bool(true)) }
        }
        return dictionaryItems(stored)
    }

    private static func layoutItems(_ stored: Any) -> [(item: String, value: SyncValue)] {
        dictionaryItems(stored)
    }

    private static func dictionaryItems(_ stored: Any) -> [(item: String, value: SyncValue)] {
        guard let dictionary = stored as? [String: Any] else {
            return []
        }
        return dictionary.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { item in
            (item, dictionary[item].flatMap { SyncValue(propertyList: $0) } ?? unrepresentable)
        }
    }

    // MARK: Profiles

    /// The profiles of the stored `LayoutProfiles`, as units of the family `prof`. Only the
    /// name and the macOS 27 part sync; the macOS 26 part, the bindings and any other field
    /// stay on this Mac (D-05).
    private static func profileItems(_ stored: Any) -> [(item: String, value: SyncValue)] {
        guard let profiles = parseProfiles(stored) else {
            return []
        }
        var seen = Set<String>()
        var items: [(item: String, value: SyncValue)] = []
        for profile in profiles {
            guard let id = profile["profileID"] as? String, !id.isEmpty, seen.insert(id).inserted else {
                continue
            }
            var fields: [String: SyncValue] = [:]
            if let name = profile["name"].flatMap({ SyncValue(propertyList: $0) }) {
                fields["name"] = name
            }
            if let sections = profile["applicationSections"].flatMap({ SyncValue(propertyList: $0) }) {
                fields["applicationSections"] = sections
            }
            if let known = profile["knownApplications"].flatMap({ SyncValue(propertyList: $0) }) {
                fields["knownApplications"] = sortedKnown(known)
            }
            items.append((id, .dictionary(fields)))
        }
        return items.sorted { $0.item.utf8.lexicographicallyPrecedes($1.item.utf8) }
    }

    /// The known applications of a profile as a sorted, unique array, which is how the set
    /// compares; anything else is returned unchanged and fails validation.
    private static func sortedKnown(_ value: SyncValue) -> SyncValue {
        guard let elements = value.arrayValue else {
            return value
        }
        let strings = elements.compactMap(\.stringValue)
        guard strings.count == elements.count else {
            return value
        }
        return .array(Array(Set(strings)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { .string($0) })
    }

    /// The stored profiles as JSON objects; `[]` when nothing is stored, `nil` when what is
    /// stored is not a JSON array of objects (it is then left alone).
    private static func parseProfiles(_ stored: Any?) -> [[String: Any]]? {
        guard let stored else {
            return []
        }
        guard
            let data = stored as? Data,
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let profiles = object as? [[String: Any]]
        else {
            return nil
        }
        return profiles
    }

    // MARK: Writes

    /// The defaults writes that apply `changes`, as the smallest set: a key appears only when
    /// its value changes. A `nil` value removes the stored key.
    ///
    /// A whole unit writes its key and a deletion removes it. A split item rewrites the
    /// stored dictionary with only that item changed and keeps every other item. A change of
    /// a unit this build does not know, of a value that is not valid or of a value over the
    /// cap is skipped and never written; the engine reports it as unusable.
    static func defaultsWrites(applying changes: [SyncUnitKey: SyncPayload], to defaults: [String: Any], table: SyncUnitTable) -> [String: Any?] {
        var writes: [String: Any?] = [:]
        var items: [String: [(item: String, payload: SyncPayload)]] = [:]
        for key in changes.keys.sorted() {
            guard let payload = changes[key], let descriptor = table.descriptor(for: key), !descriptor.isSet else {
                continue
            }
            switch key {
            case .whole(let unit):
                guard isAcceptable(payload, item: nil, descriptor: descriptor) else {
                    continue
                }
                writeWhole(unit, payload, table: table, into: &writes)
            case .split(let family, let item):
                guard isAcceptable(payload, item: item, descriptor: descriptor) else {
                    continue
                }
                items[family, default: []].append((item, payload))
            }
        }
        for family in items.keys.sorted() {
            writeFamily(family, items[family] ?? [], defaults: defaults, into: &writes)
        }
        return writes
    }

    /// The write that adds `set` to the stored `KnownApplications27`, which never loses an
    /// element (D-06); empty when nothing is new. The array is sorted and unique.
    static func knownApplicationsUnion(_ set: [String], into defaults: [String: Any]) -> [String: Any?] {
        let key = Defaults.Key.knownApplications27.rawValue
        let current = defaults[key] as? [String] ?? []
        let union = Set(current).union(set.filter(SyncUnitTable.isItemKey))
        guard union != Set(current) else {
            return [:]
        }
        return [key: union.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }]
    }

    private static func isAcceptable(_ payload: SyncPayload, item: String?, descriptor: SyncUnitDescriptor) -> Bool {
        switch payload {
        case .deleted:
            true
        case .value(let value):
            descriptor.validate(item, value) && !descriptor.isOverCap(value)
        }
    }

    private static func remove(_ key: String, from writes: inout [String: Any?]) {
        writes.updateValue(nil, forKey: key)
    }

    private static func writeWhole(_ unit: String, _ payload: SyncPayload, table: SyncUnitTable, into writes: inout [String: Any?]) {
        if unit == SyncUnitTable.holzBarIconUnit {
            let fields: [String: SyncValue]
            switch payload {
            case .deleted:
                fields = [:]
            case .value(let value):
                fields = value.dictionaryValue ?? [:]
            }
            if let icon = fields[SyncNormalizers.iconField] {
                writes[Defaults.Key.holzBarIcon.rawValue] = icon.propertyList
            } else {
                remove(Defaults.Key.holzBarIcon.rawValue, from: &writes)
            }
            if let template = fields[SyncNormalizers.templateField] {
                writes[Defaults.Key.customHolzBarIconIsTemplate.rawValue] = template.propertyList
            } else {
                remove(Defaults.Key.customHolzBarIconIsTemplate.rawValue, from: &writes)
            }
            return
        }
        guard let key = table.storedKey(forUnit: unit) else {
            return
        }
        switch payload {
        case .deleted:
            remove(key.rawValue, from: &writes)
        case .value(let value):
            writes[key.rawValue] = value.propertyList
        }
    }

    private static func writeFamily(
        _ family: String,
        _ changes: [(item: String, payload: SyncPayload)],
        defaults: [String: Any],
        into writes: inout [String: Any?]
    ) {
        switch family {
        case Defaults.Key.revealOnChangeItems.rawValue:
            writeMarks(changes, defaults: defaults, into: &writes)
        case SyncUnitTable.profilesFamily:
            writeProfiles(changes, defaults: defaults, into: &writes)
        case SyncUnitTable.layout27Family:
            writeDictionary(Defaults.Key.macOS27Layout.rawValue, changes, defaults: defaults, into: &writes) { payload in
                // Visible is the absence of a stored section.
                if case .value(let value) = payload, let section = value.integerValue, section != 0 {
                    return Int(section)
                }
                return nil
            }
        default:
            writeDictionary(family, changes, defaults: defaults, into: &writes) { payload in
                if case .value(let value) = payload {
                    return value.propertyList
                }
                return nil
            }
        }
    }

    /// Rewrites the stored dictionary of `key` with the changed items only.
    private static func writeDictionary(
        _ key: String,
        _ changes: [(item: String, payload: SyncPayload)],
        defaults: [String: Any],
        into writes: inout [String: Any?],
        stored: (SyncPayload) -> Any?
    ) {
        let current = defaults[key]
        var dictionary = current as? [String: Any] ?? [:]
        for (item, payload) in changes {
            dictionary[item] = stored(payload)
        }
        guard !isSame(current, dictionary), !(current == nil && dictionary.isEmpty) else {
            return
        }
        writes[key] = dictionary
    }

    /// Adds and removes items of the stored `RevealOnChangeItems` array.
    private static func writeMarks(_ changes: [(item: String, payload: SyncPayload)], defaults: [String: Any], into writes: inout [String: Any?]) {
        let key = Defaults.Key.revealOnChangeItems.rawValue
        let current = defaults[key]
        var marked = Set((current as? [Any] ?? []).compactMap { $0 as? String })
        for (item, payload) in changes {
            if case .value(let value) = payload, value.boolValue == true {
                marked.insert(item)
            } else {
                marked.remove(item)
            }
        }
        let sorted = marked.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard !isSame(current, sorted), !(current == nil && sorted.isEmpty) else {
            return
        }
        writes[key] = sorted
    }

    /// Replaces the name and the macOS 27 part of the profiles with the given IDs, adds
    /// unknown IDs, removes deleted ones, and keeps everything else of every profile: the
    /// macOS 26 part, the bindings and fields this build does not know (D-05).
    private static func writeProfiles(_ changes: [(item: String, payload: SyncPayload)], defaults: [String: Any], into writes: inout [String: Any?]) {
        let key = Defaults.Key.layoutProfiles.rawValue
        let current = defaults[key]
        guard var profiles = parseProfiles(current) else {
            return
        }
        for (id, payload) in changes {
            let index = profiles.firstIndex { ($0["profileID"] as? String) == id }
            switch payload {
            case .deleted:
                profiles.removeAll { ($0["profileID"] as? String) == id }
            case .value(let value):
                guard let fields = value.dictionaryValue, let name = fields["name"]?.stringValue else {
                    continue
                }
                var profile = index.map { profiles[$0] } ?? ["profileID": id, "itemSections": [String: Int]()]
                profile["name"] = name
                profile["applicationSections"] = (fields["applicationSections"]?.dictionaryValue ?? [:]).compactMapValues { $0.integerValue.map { Int($0) } }
                if let known = fields["knownApplications"]?.arrayValue {
                    profile["knownApplications"] = known.compactMap(\.stringValue)
                } else {
                    profile["knownApplications"] = nil
                }
                if let index {
                    profiles[index] = profile
                } else {
                    profiles.append(profile)
                }
            }
        }
        profiles.sort(by: profilesAreInOrder)
        guard let oldProfiles = parseProfiles(current), !(oldProfiles as NSArray).isEqual(to: profiles) else {
            return
        }
        if profiles.isEmpty {
            remove(key, from: &writes)
        } else if let data = try? JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys, .withoutEscapingSlashes]) {
            writes[key] = data
        }
    }

    /// The order `LayoutProfiles` keeps: by name, then by profile ID.
    private static func profilesAreInOrder(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        let leftName = lhs["name"] as? String ?? ""
        let rightName = rhs["name"] as? String ?? ""
        switch leftName.localizedStandardCompare(rightName) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return (lhs["profileID"] as? String ?? "") < (rhs["profileID"] as? String ?? "")
        }
    }

    private static func isSame(_ stored: Any?, _ new: Any) -> Bool {
        guard let stored else {
            return false
        }
        guard let left = SyncValue(propertyList: stored), let right = SyncValue(propertyList: new) else {
            return false
        }
        return left == right
    }

    // MARK: Legacy

    /// The settings units a legacy file (`holzBar/Settings.plist` of 0.0.6 and 0.0.7-beta1)
    /// holds, to found a group from it.
    ///
    /// Only the settings units are mapped: the arrangement, the profiles, the learned keys,
    /// the flags and every local key in the file are ignored (analysis section 4.6.8). Profile
    /// hotkeys are keyed by profile name there, not by profile ID, so they are ignored too.
    static func units(fromLegacySettings settings: [String: SyncValue], table: SyncUnitTable) -> [SyncUnitKey: SyncValue] {
        let defaults = settings.mapValues(\.propertyList)
        var units = snapshot(defaults: defaults, table: table, generation: .g26)
        for key in units.keys {
            if case .split(let family, let item) = key, family == Defaults.Key.hotkeys.rawValue, item.hasPrefix(SyncUnitTable.applyProfilePrefix) {
                units[key] = nil
            }
        }
        return units
    }
}
