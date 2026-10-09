//
//  UnitTableTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncUnitTable")
struct UnitTableTests {
    private let table = SyncUnitTable.version1(normalizers: .canonical)

    private static let wholeUnits: Set<String> = [
        // General
        "ShowIceIcon", "UseIceBar", "IceBarLocation", "IceBarDisplays", "ShowsNotchOverflowInIceBar",
        "ShowOnClick", "ShowOnHover", "ShowOnScroll", "ShowOnHoverDelay", "AutoRehide", "RehideStrategy",
        "RehideInterval", "TempShowInterval", "ItemSpacingOffset", "HolzBarIconShowsCaptureDot",
        // Advanced
        "EnableAlwaysHiddenSection", "ShowAllSectionsOnUserDrag", "SectionDividerStyle", "HideApplicationMenus",
        "KeepsDockIconHidden", "EnableSecondaryContextMenu", "NewItemsPlacement", "KeepLiveActivitiesVisible",
        "AutoZenWhileSharingScreen", "OpenHiddenItemsInMenuBar", "SpacerCount", "SpacerWidth",
    ]

    private static let jsonUnits: Set<String> = ["MenuBarAppearanceConfigurationV2", "ItemGroups"]
    private static let iconParts: Set<String> = ["IceIcon", "CustomIceIconIsTemplate"]
    private static let splitFamilies: Set<String> = ["Hotkeys", "ItemIcons", "RevealRules", "RevealOnChangeItems"]

    private static let expectedLocal: [String: SyncLocalReason] = [
        "ItemSections": .arrangement26,
        "KnownItemTags": .learned,
        "TitleChangingItemOwners": .learned,
        "MacOS27LayoutSeeded": .flag,
        "hasMigrated0_8_0": .flag,
        "hasMigrated0_10_0": .flag,
        "hasMigrated0_10_1": .flag,
        "hasMigrated0_11_10": .flag,
        "hasMigrated0_11_13": .flag,
        "hasMigrated0_11_13_1": .flag,
        "HasImportedIceSettings": .flag,
        "CurrentLayoutProfile": .profileContext,
        "MacOS27ClickRestoreDelay": .tuning,
        "MacOS27IceBarWaitsForRefresh": .tuning,
        "SyncsSettingsWithICloud": .localSetting,
        "DebugDropsBarrierExitEvent": .localSetting,
        "DebugHangsItemImageCapture": .localSetting,
        "MenuBarHasBorder": .iceEra,
        "MenuBarBorderColor": .iceEra,
        "MenuBarBorderWidth": .iceEra,
        "MenuBarHasShadow": .iceEra,
        "MenuBarTintKind": .iceEra,
        "MenuBarTintColor": .iceEra,
        "MenuBarTintGradient": .iceEra,
        "MenuBarShapeKind": .iceEra,
        "MenuBarFullShapeInfo": .iceEra,
        "MenuBarSplitShapeInfo": .iceEra,
        "MenuBarAppearanceConfiguration": .iceEra,
        "ShowSectionDividers": .iceEra,
        "CanToggleAlwaysHiddenSection": .iceEra,
        "Sections": .iceEra,
    ]

    // MARK: R-CLASS-1

    @Test("Every Defaults.Key has exactly one class, and the synced set is the unit table")
    func everyKeyHasOneClass() {
        var whole = Set<String>()
        var json = Set<String>()
        var icon = Set<String>()
        var split = Set<String>()
        var layout = Set<String>()
        var profiles = Set<String>()
        var known = Set<String>()
        var local: [String: SyncLocalReason] = [:]
        for key in Defaults.Key.allCases {
            switch SyncUnitTable.keyClass(key) {
            case .whole(let unit):
                #expect(unit == key.rawValue)
                if Self.jsonUnits.contains(unit) {
                    json.insert(unit)
                } else {
                    whole.insert(unit)
                }
            case .holzBarIconPart:
                icon.insert(key.rawValue)
            case .split(let family):
                #expect(family == key.rawValue)
                split.insert(family)
            case .layout27:
                layout.insert(key.rawValue)
            case .profiles:
                profiles.insert(key.rawValue)
            case .knownApplications27:
                known.insert(key.rawValue)
            case .local(let reason):
                local[key.rawValue] = reason
            }
        }
        #expect(whole == Self.wholeUnits)
        #expect(whole.count == 27)
        #expect(json == Self.jsonUnits)
        #expect(icon == Self.iconParts)
        #expect(split == Self.splitFamilies)
        #expect(layout == ["MacOS27Layout"])
        #expect(profiles == ["LayoutProfiles"])
        #expect(known == ["KnownApplications27"])
        #expect(local == Self.expectedLocal)
        let classified = whole.count + json.count + icon.count + split.count + layout.count + profiles.count + known.count + local.count
        #expect(classified == Defaults.Key.allCases.count)
    }

    @Test("A synced key never starts with an excluded prefix")
    func syncedKeysAreNotExcluded() {
        #expect(SyncUnitTable.excludedKeyPrefixes == ["NSWindow Frame", "NSStatusItem Preferred Position", "NSStatusItem Visible", "SU", "SettingsSync"])
        for key in Defaults.Key.allCases {
            #expect(!SyncUnitTable.isExcluded(storedKey: key.rawValue), "\(key.rawValue)")
        }
        #expect(SyncUnitTable.isExcluded(storedKey: "SettingsSyncDeviceID"))
        #expect(SyncUnitTable.isExcluded(storedKey: "SUEnableAutomaticChecks"))
        #expect(SyncUnitTable.isExcluded(storedKey: "NSWindow Frame Settings"))
    }

    // MARK: The list of synced keys

    /// The repository root, from this file's path (`Tests/HolzBarCoreTests/Sync/`).
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The raw value of every `Defaults.Key` whose class is not local, sorted by UTF-8 bytes.
    private static var syncedKeyList: [String] {
        Defaults.Key.allCases
            .filter { key in
                if case .local = SyncUnitTable.keyClass(key) {
                    return false
                }
                return true
            }
            .map(\.rawValue)
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    @Test("The checked-in list of synced keys is the unit table's (SYNC_WRITE_KEYS=1 rewrites it)")
    func syncedKeyFileMatchesTable() throws {
        let url = Self.repositoryRoot.appendingPathComponent(".github/sync-synced-keys.txt")
        let expected = Self.syncedKeyList
        if ProcessInfo.processInfo.environment["SYNC_WRITE_KEYS"] == "1" {
            try (expected.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let listed = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let missing = Set(expected).subtracting(listed).sorted()
        let extra = Set(listed).subtracting(expected).sorted()
        #expect(missing.isEmpty, "Keys of the unit table that .github/sync-synced-keys.txt lacks: \(missing)")
        #expect(extra.isEmpty, "Keys of .github/sync-synced-keys.txt that the unit table does not sync: \(extra)")
        #expect(listed == expected, "The list is sorted, one key per line, without duplicates")
    }

    @Test("The table is version 1")
    func version() {
        #expect(table.version == 1)
    }

    // MARK: Descriptors

    @Test("Every whole unit and family has a descriptor; unknown units have none")
    func descriptors() {
        for name in Self.wholeUnits.union(Self.jsonUnits).union(["HolzBarIcon"]) {
            #expect(table.descriptor(for: .whole(name)) != nil, "\(name)")
        }
        for family in Self.splitFamilies.subtracting(["RevealRules"]) {
            #expect(table.descriptor(for: .split(family: family, item: "OpenItem:a")) != nil, "\(family)")
        }
        #expect(table.descriptor(for: .split(family: "ItemIcons", item: "ns:Title")) != nil)
        #expect(table.descriptor(for: .split(family: "RevealRules", item: "Offline")) != nil)
        #expect(table.descriptor(for: .split(family: "RevealRules", item: "FutureRule")) == nil)
        #expect(table.descriptor(for: .whole("FutureSetting")) == nil)
        #expect(table.descriptor(for: .split(family: "FutureFamily", item: "a")) == nil)
        #expect(table.descriptor(for: .split(family: "Hotkeys", item: "FutureAction")) == nil)
        #expect(table.descriptor(for: .whole("ItemSections")) == nil)
        #expect(table.descriptor(for: .whole("SettingsSyncDeviceID")) == nil)
    }

    @Test("The caps of the units")
    func caps() throws {
        #expect(table.descriptor(for: .whole("MenuBarAppearanceConfigurationV2"))?.cap == 64 << 10)
        #expect(table.descriptor(for: .whole("ItemGroups"))?.cap == 64 << 10)
        #expect(table.descriptor(for: .whole("HolzBarIcon"))?.cap == 256 << 10)
        #expect(table.descriptor(for: .split(family: "Hotkeys", item: "OpenItem:a"))?.maximumItems == 1024)
        #expect(table.descriptor(for: .split(family: "prof", item: "id"))?.cap == 64 << 10)
    }

    @Test("The holzBar icon is one value of the image and its flag, at most 256 KiB")
    func iconUnit() throws {
        let descriptor = try #require(table.descriptor(for: .whole("HolzBarIcon")))
        let atCap = SyncValue.dictionary(["icon": .data(Data(count: 256 << 10)), "template": .bool(true)])
        let overCap = SyncValue.dictionary(["icon": .data(Data(count: (256 << 10) + 1)), "template": .bool(true)])
        #expect(!descriptor.isOverCap(atCap))
        #expect(descriptor.isOverCap(overCap))
        #expect(descriptor.size(of: overCap) == (256 << 10) + 1)
        #expect(descriptor.validate(nil, atCap))
        #expect(!descriptor.validate(nil, .dictionary(["icon": .string("x")])))
        #expect(!descriptor.validate(nil, .dictionary([:])))
        #expect(!descriptor.validate(nil, .bool(true)))
    }

    @Test("Appearance and groups normalize to equal digests whatever the key order")
    func jsonNormalization() throws {
        let first = SyncValue.data(Data(#"{"b":1,"a":{"y":2,"x":[1,2]}}"#.utf8))
        let second = SyncValue.data(Data(#"{ "a": {"x":[1,2], "y":2}, "b": 1 }"#.utf8))
        let normalizers = SyncNormalizers.canonical
        let left = try #require(normalizers.appearance(first))
        let right = try #require(normalizers.appearance(second))
        #expect(left.digest == right.digest)
        #expect(normalizers.itemGroups(first)?.digest == normalizers.itemGroups(second)?.digest)
        #expect(normalizers.appearance(.data(Data("not json".utf8))) == nil)
        #expect(normalizers.appearance(.string("{}")) == nil)
        #expect(normalizers.appearance(.data(Data("42".utf8))) == nil)
        let descriptor = try #require(table.descriptor(for: .whole("ItemGroups")))
        #expect(descriptor.validate(nil, first))
        #expect(!descriptor.validate(nil, .data(Data("{".utf8))))
    }

    // MARK: Scope

    @Test("l27, prof and known27 are authored and applied on macOS 27 only")
    func scopes() {
        let layout = SyncUnitKey.split(family: "l27", item: "com.a")
        let profile = SyncUnitKey.split(family: "prof", item: "ID")
        let known = SyncUnitKey.whole("known27")
        for key in [layout, profile, known] {
            #expect(!table.isAuthoredHere(key, generation: .g26), "\(key)")
            #expect(table.isAuthoredHere(key, generation: .g27), "\(key)")
            #expect(!table.isApplicableHere(key, generation: .g26), "\(key)")
            #expect(table.isApplicableHere(key, generation: .g27), "\(key)")
        }
        #expect(!table.isKnownApplicationsApplicable(generation: .g26))
        #expect(table.isKnownApplicationsApplicable(generation: .g27))
        for key in [SyncUnitKey.whole("ShowOnHover"), .whole("HolzBarIcon"), .split(family: "Hotkeys", item: "OpenItem:a")] {
            #expect(table.isAuthoredHere(key, generation: .g26))
            #expect(table.isAuthoredHere(key, generation: .g27))
            #expect(table.isApplicableHere(key, generation: .g26))
            #expect(table.isApplicableHere(key, generation: .g27))
        }
        #expect(!table.isAuthoredHere(.whole("FutureSetting"), generation: .g27))
    }

    @Test("The generation follows the backend")
    func generation() {
        #expect(SyncGeneration(backend: .accessibility27) == .g27)
        #expect(SyncGeneration(backend: .service26) == .g26)
        #expect(SyncGeneration(backend: .windowList) == .g26)
    }

    // MARK: Validation

    @Test("Whole units are validated by kind and range")
    func wholeValidation() throws {
        let hover = try #require(table.descriptor(for: .whole("ShowOnHover")))
        #expect(hover.validate(nil, .bool(true)))
        #expect(!hover.validate(nil, .integer(1)))
        let interval = try #require(table.descriptor(for: .whole("RehideInterval")))
        #expect(interval.validate(nil, .real(15)))
        #expect(interval.validate(nil, .integer(30)))
        #expect(!interval.validate(nil, .integer(31)))
        #expect(!interval.validate(nil, .string("5")))
        let count = try #require(table.descriptor(for: .whole("SpacerCount")))
        #expect(count.validate(nil, .integer(10)))
        #expect(!count.validate(nil, .real(2.5)))
    }
}
