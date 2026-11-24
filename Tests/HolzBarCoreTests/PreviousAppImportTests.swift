import Foundation
import Testing
@testable import HolzBarCore

@Suite("PreviousAppImport")
struct PreviousAppImportTests {
    /// holzBar's bundle identifier, which the app passes as `Constants.bundleIdentifier`.
    private let ownBundle = "com.holzcloud.holzBar"
    /// The prefixes the app passes as `SettingsBackup.excludedKeyPrefixes`.
    private let excluded = ["NSWindow Frame", "NSStatusItem Preferred Position", "NSStatusItem Visible", "SU"]

    /// The twelve Boolean settings of Thaw that have a target in holzBar, by the stored name.
    private let booleanNames = [
        "AutoRehide",
        "AutoZenWhileSharingScreen",
        "EnableAlwaysHiddenSection",
        "EnableSecondaryContextMenu",
        "HideApplicationMenus",
        "OpenHiddenItemsInMenuBar",
        "ShowAllSectionsOnUserDrag",
        "ShowOnClick",
        "ShowOnHover",
        "ShowOnScroll",
        "ShowIceIcon",
        "UseIceBar",
    ]

    /// The numeric settings of Thaw that have a target in holzBar, by the stored name.
    private let numberNames = ["RehideInterval", "ShowOnHoverDelay", "TempShowInterval"]

    /// A Thaw defaults domain built from the upstream key table (D-17): the shared names, and the
    /// keys only Thaw has.
    private func thawFixture(booleans: Bool) -> [String: Any] {
        var settings: [String: Any] = [:]
        for name in booleanNames {
            settings[name] = booleans
        }
        settings["LastActiveProfileID"] = "7F1B5C24-0000-4000-8000-000000000001"
        settings["KnownDisplays"] = [["id": "A", "name": "Display"]]
        settings["GlobalPreProfileHook"] = "/usr/bin/true"
        settings["GlobalPostProfileHook"] = "/usr/bin/true"
        settings["ThawBarLocation"] = 1
        settings["NewItemsPlacementData"] = "section"
        settings["SectionDividerStyle"] = 1
        settings["IceIcon"] = Data([1, 2, 3])
        settings["CustomIceIconIsTemplate"] = true
        settings["NSWindow Frame Settings"] = "10 10 600 400 0 0 1440 900"
        settings["NSStatusItem Preferred Position Item-0"] = 120.0
        return settings
    }

    /// What holzBar has now: every one of the twelve targets, all off.
    private var allOff: [Defaults.Key: ImportValue] {
        [
            .autoRehide: .bool(false),
            .autoZenWhileSharingScreen: .bool(false),
            .enableAlwaysHiddenSection: .bool(false),
            .enableSecondaryContextMenu: .bool(false),
            .hideApplicationMenus: .bool(false),
            .openHiddenItemsInMenuBar: .bool(false),
            .showAllSectionsOnUserDrag: .bool(false),
            .showOnClick: .bool(false),
            .showOnHover: .bool(false),
            .showOnScroll: .bool(false),
            .showHolzBarIcon: .bool(false),
            .useShelf: .bool(false),
        ]
    }

    /// What holzBar has now for the numbers and the strategy: the defaults of the app.
    private var numbersNow: [Defaults.Key: ImportValue] {
        [
            .rehideInterval: .number(15),
            .showOnHoverDelay: .number(0.2),
            .tempShowInterval: .number(15),
            .rehideStrategy: .choice(0),
        ]
    }

    /// The stored form of a hotkey combination: the JSON array `[key, modifiers]`, as
    /// `HotkeyStorage.encode` writes it (that file is not part of the Linux list).
    private func combination(_ key: Int, _ modifiers: Int) -> Data {
        Data("[\(key),\(modifiers)]".utf8)
    }

    /// The actions the importer hands in: two of holzBar's, as the app builds them from
    /// `HotkeyAction` and the catalogue.
    private let knownActions: Set<String> = ["ToggleHiddenSection", "SearchMenuBarItems", "EnableIceBar"]

    /// The rules of the importer, reduced to what the tests need: a combination is valid when it
    /// is a JSON array of two integers whose modifier is not zero.
    private var hotkeyRules: ImportHotkeyRules {
        ImportHotkeyRules(knownActions: knownActions) { data in
            guard let values = try? JSONDecoder().decode([Int].self, from: data), values.count == 2 else {
                return false
            }
            return (0...127).contains(values[0]) && values[1] != 0
        }
    }

    private func plan(
        _ settings: [String: Any],
        current: [Defaults.Key: ImportValue],
        hotkeys: [String: Data] = [:]
    ) -> ImportPlan {
        PreviousAppImport.plan(
            source: .thaw,
            settings: settings,
            current: current,
            currentHotkeys: hotkeys,
            hotkeyRules: hotkeyRules,
            excludedPrefixes: excluded,
            ownBundleIdentifier: ownBundle
        )
    }

    @Test("Thaw's bundle identifier and name are pinned (flagged assumption A12)")
    func thawIdentity() {
        #expect(ImportSource.thaw.bundleIdentifier == "com.stonerl.Thaw")
        #expect(ImportSource.thaw.productName == "Thaw")
        #expect(ImportSource.thaw.rawValue == "thaw")
    }

    @Test("A Boolean that differs from the current value is one change and one write")
    func booleanChangeIsOneWrite() {
        let result = plan(["ShowOnHover": true], current: allOff)
        #expect(result.changes == [ImportChange(key: .showOnHover, hotkeyAction: nil, before: .bool(false), after: .bool(true))])
        #expect(result.writes.keys.sorted() == [Defaults.Key.showOnHover.rawValue])
        #expect(result.writes["ShowOnHover"] as? Bool == true)
        #expect(result.ignoredCount == 0)
        #expect(result.omissions.isEmpty)
    }

    @Test("A value equal to the current one gives neither a change nor an ignored count")
    func equalValueIsSilent() {
        let result = plan(["ShowOnHover": false, "ShowOnClick": true], current: allOff)
        #expect(result.changes.map(\.key) == [.showOnClick])
        #expect(result.writes.keys.sorted() == ["ShowOnClick"])
        #expect(result.ignoredCount == 0)
    }

    @Test("A String or a number under a Boolean key is ignored and counted")
    func wrongKindIsIgnored() {
        let result = plan(["ShowOnHover": "yes", "ShowOnClick": 1, "ShowOnScroll": true], current: allOff)
        #expect(result.changes.map(\.key) == [.showOnScroll])
        #expect(result.writes.keys.sorted() == ["ShowOnScroll"])
        #expect(result.ignoredCount == 2)
    }

    @Test("A key with no entry in current (no label on this macOS) is ignored and counted")
    func unlabelledTargetIsIgnored() {
        var current = allOff
        current[.showAllSectionsOnUserDrag] = nil
        let result = plan(["ShowAllSectionsOnUserDrag": true, "ShowOnClick": true], current: current)
        #expect(result.changes.map(\.key) == [.showOnClick])
        #expect(result.writes["ShowAllSectionsOnUserDrag"] == nil)
        #expect(result.ignoredCount == 1)
    }

    @Test("Thaw-only keys, window frames, item positions and hooks are ignored and never written")
    func neverImportedKeys() {
        let settings = thawFixture(booleans: true)
        let result = plan(settings, current: allOff)
        let never = [
            "LastActiveProfileID", "KnownDisplays", "GlobalPreProfileHook", "GlobalPostProfileHook",
            "ThawBarLocation", "NewItemsPlacementData", "SectionDividerStyle", "IceIcon",
            "CustomIceIconIsTemplate", "NSWindow Frame Settings", "NSStatusItem Preferred Position Item-0",
        ]
        for name in never {
            #expect(result.writes[name] == nil, "\(name) must not be written")
        }
        #expect(result.changes.count == 12)
        #expect(result.ignoredCount == never.count)
        #expect(result.writes.count == 12)
    }

    @Test("A key under an excluded prefix is ignored even when it looks like a setting")
    func excludedPrefixWins() {
        let result = plan(["SUEnableAutomaticChecks": true, "NSStatusItem Visible Item-0": true], current: allOff)
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 2)
    }

    @Test("The writes are exactly the raw values of the changes, and holzBar's validation ignores none of them")
    func writesAreValidated() {
        let result = plan(thawFixture(booleans: true), current: allOff)
        #expect(result.writes.keys.sorted() == result.changes.map(\.key.rawValue).sorted())
        let validated = Defaults.Key.validatedSettings(result.writes, ownBundleIdentifier: ownBundle)
        #expect(validated.ignored.isEmpty)
        #expect(validated.accepted.count == result.writes.count)
    }

    @Test("The import only carries keys: nothing is removed, and settings Thaw lacks are not touched")
    func mergeCarriesOnlyTheKeysOfTheSource() {
        let result = plan(["ShowOnClick": true], current: allOff)
        #expect(result.writes.keys.sorted() == ["ShowOnClick"])
        #expect(result.changes.count == 1)
    }

    @Test("An empty domain gives an empty plan")
    func emptyDomain() {
        let result = plan([:], current: allOff)
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 0)
        #expect(result.source == .thaw)
    }

    @Test("Every rule of Thaw's table reads the stored name its target stores under")
    func thawNamesAreTheTargetsRawValues() {
        let names = PreviousAppImport.sourceNames(of: .thaw)
        #expect(Set(names.keys) == Set(booleanNames + numberNames + ["RehideStrategy"]))
        for (name, target) in names {
            #expect(name == target.rawValue)
        }
    }

    @Test("RehideInterval 99 is written clamped to 30, ShowOnHoverDelay -1 clamped to 0, TempShowInterval 5 as 5")
    func numbersAreClamped() throws {
        let current = allOff.merging(numbersNow) { first, _ in first }
        let result = plan(["RehideInterval": 99, "ShowOnHoverDelay": -1, "TempShowInterval": 5], current: current)
        #expect(result.changes == [
            ImportChange(key: .rehideInterval, hotkeyAction: nil, before: .number(15), after: .number(30)),
            ImportChange(key: .showOnHoverDelay, hotkeyAction: nil, before: .number(0.2), after: .number(0)),
            ImportChange(key: .tempShowInterval, hotkeyAction: nil, before: .number(15), after: .number(5)),
        ])
        #expect(try #require(result.writes["RehideInterval"] as? NSNumber).doubleValue == 30)
        #expect(try #require(result.writes["ShowOnHoverDelay"] as? NSNumber).doubleValue == 0)
        #expect(try #require(result.writes["TempShowInterval"] as? NSNumber).doubleValue == 5)
        #expect(result.ignoredCount == 0)
        let validated = Defaults.Key.validatedSettings(result.writes, ownBundleIdentifier: ownBundle)
        #expect(validated.ignored.isEmpty)
    }

    @Test("A non-finite number, a String or a Boolean under a number key is ignored and counted")
    func wrongNumbersAreIgnored() {
        let current = allOff.merging(numbersNow) { first, _ in first }
        let result = plan(
            ["RehideInterval": Double.infinity, "ShowOnHoverDelay": Double.nan, "TempShowInterval": "5", "RehideStrategy": true],
            current: current
        )
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 4)
    }

    @Test("A number equal to the current one is silent")
    func equalNumberIsSilent() {
        let current = allOff.merging(numbersNow) { first, _ in first }
        let result = plan(["RehideInterval": 15, "TempShowInterval": 15.0], current: current)
        #expect(result.changes.isEmpty)
        #expect(result.ignoredCount == 0)
    }

    @Test("RehideStrategy 1 becomes a choice; 7, -1 and 1.5 are ignored and counted")
    func strategyIsAChoice() throws {
        let current = allOff.merging(numbersNow) { first, _ in first }
        let accepted = plan(["RehideStrategy": 1], current: current)
        #expect(accepted.changes == [ImportChange(key: .rehideStrategy, hotkeyAction: nil, before: .choice(0), after: .choice(1))])
        #expect(try #require(accepted.writes["RehideStrategy"] as? NSNumber).intValue == 1)
        // A huge or non-finite value is refused without converting it to an Int.
        for huge in [1e300, -1e300, Double.infinity, Double.nan] {
            let refused = plan(["RehideStrategy": huge], current: current)
            #expect(refused.changes.isEmpty)
            #expect(refused.ignoredCount == 1)
        }
        for value in [7, -1] as [Int] {
            let refused = plan(["RehideStrategy": value], current: current)
            #expect(refused.changes.isEmpty)
            #expect(refused.writes.isEmpty)
            #expect(refused.ignoredCount == 1)
        }
        let fraction = plan(["RehideStrategy": 1.5], current: current)
        #expect(fraction.changes.isEmpty)
        #expect(fraction.ignoredCount == 1)
    }

    @Test("A strategy equal to the current one is silent")
    func equalStrategyIsSilent() {
        let current = allOff.merging(numbersNow) { first, _ in first }
        let result = plan(["RehideStrategy": 0], current: current)
        #expect(result.changes.isEmpty)
        #expect(result.ignoredCount == 0)
    }

    @Test("Numbers and the strategy are ignored when they have no label here")
    func unlabelledNumbersAreIgnored() {
        let result = plan(["RehideInterval": 20, "RehideStrategy": 2], current: allOff)
        #expect(result.changes.isEmpty)
        #expect(result.ignoredCount == 2)
    }

    @Test("The changes are in a fixed order whatever order the dictionary iterates in")
    func changesAreSorted() {
        let result = plan(thawFixture(booleans: true), current: allOff)
        #expect(result.changes.map(\.key.rawValue) == result.changes.map(\.key.rawValue).sorted())
    }

    // MARK: Hotkeys

    @Test("A known action with a valid combination that differs is one composite change and a merged write")
    func hotkeyChangesPerAction() throws {
        let mine = combination(4, 256)
        let theirs = combination(40, 768)
        let result = plan(["Hotkeys": ["ToggleHiddenSection": theirs]], current: allOff, hotkeys: ["ToggleHiddenSection": mine])
        #expect(result.changes == [
            ImportChange(key: .hotkeys, hotkeyAction: "ToggleHiddenSection", before: .composite, after: .composite),
        ])
        let written = try #require(result.writes["Hotkeys"] as? [String: Data])
        #expect(written == ["ToggleHiddenSection": theirs])
        #expect(result.ignoredCount == 0)
    }

    @Test("Every holzBar hotkey the source lacks stays, item and profile hotkeys included")
    func mergeKeepsTheOtherHotkeys() throws {
        let kept = combination(1, 256)
        let keptItem = combination(2, 512)
        let mine = ["SearchMenuBarItems": kept, "Item:com.example.app": keptItem, "ToggleHiddenSection": combination(4, 256)]
        let result = plan(["Hotkeys": ["ToggleHiddenSection": combination(40, 768)]], current: allOff, hotkeys: mine)
        let written = try #require(result.writes["Hotkeys"] as? [String: Data])
        #expect(written["SearchMenuBarItems"] == kept)
        #expect(written["Item:com.example.app"] == keptItem)
        #expect(written["ToggleHiddenSection"] == combination(40, 768))
        #expect(written.count == 3)
    }

    @Test("An action that holzBar has no entry for is ignored and counted, never written")
    func unknownActionIsIgnored() {
        let result = plan(["Hotkeys": ["ToggleThawOnly": combination(40, 768)]], current: allOff)
        #expect(result.changes.isEmpty)
        #expect(result.writes["Hotkeys"] == nil)
        #expect(result.ignoredCount == 1)
    }

    @Test("A combination that is not data, is not two integers, is out of range or has no modifier is ignored and counted")
    func invalidCombinationsAreIgnored() {
        let hotkeys: [String: Any] = [
            "ToggleHiddenSection": "not data",
            "SearchMenuBarItems": Data("[1]".utf8),
            "EnableIceBar": combination(500, 256),
            "ToggleThawOnly": combination(40, 0),
        ]
        let result = plan(["Hotkeys": hotkeys], current: allOff)
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 4)
        let bare = plan(["Hotkeys": ["ToggleHiddenSection": combination(40, 0)]], current: allOff)
        #expect(bare.changes.isEmpty)
        #expect(bare.ignoredCount == 1)
    }

    @Test("An action whose combination equals holzBar's gives nothing and is not counted as ignored")
    func equalHotkeyIsSilent() {
        let same = combination(4, 256)
        let result = plan(["Hotkeys": ["ToggleHiddenSection": same]], current: allOff, hotkeys: ["ToggleHiddenSection": same])
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 0)
    }

    @Test("Several actions are several changes, in a fixed order, and settings and hotkeys count together")
    func hotkeysAndSettingsTogether() throws {
        let result = plan(
            [
                "ShowOnClick": true,
                "Hotkeys": [
                    "SearchMenuBarItems": combination(1, 256),
                    "ToggleHiddenSection": combination(2, 256),
                    "ToggleThawOnly": combination(3, 256),
                ],
                "IceIcon": Data([1]),
            ],
            current: allOff
        )
        #expect(result.changes.map(\.key) == [.hotkeys, .hotkeys, .showOnClick])
        #expect(result.changes.compactMap(\.hotkeyAction) == ["SearchMenuBarItems", "ToggleHiddenSection"])
        #expect(result.ignoredCount == 2)
        let written = try #require(result.writes["Hotkeys"] as? [String: Data])
        #expect(written.keys.sorted() == ["SearchMenuBarItems", "ToggleHiddenSection"])
        let validated = Defaults.Key.validatedSettings(result.writes, ownBundleIdentifier: ownBundle)
        #expect(validated.ignored.isEmpty)
    }

    @Test("A Hotkeys value that is not a dictionary is one ignored key; an empty one is nothing")
    func hotkeysOfTheWrongKind() {
        let wrong = plan(["Hotkeys": "x"], current: allOff)
        #expect(wrong.changes.isEmpty)
        #expect(wrong.ignoredCount == 1)
        let empty = plan(["Hotkeys": [String: Any]()], current: allOff)
        #expect(empty.changes.isEmpty)
        #expect(empty.ignoredCount == 0)
    }

    // MARK: Not imported and nothing to change

    @Test("Thaw's menu bar appearance is one omission, neither written nor counted as ignored")
    func appearanceIsOmitted() {
        let result = plan(["MenuBarAppearanceConfigurationV2": Data([1, 2, 3]), "ShowOnClick": true], current: allOff)
        #expect(result.omissions == [ImportOmission(key: .menuBarAppearanceConfigurationV2, hotkeyAction: nil)])
        #expect(result.writes["MenuBarAppearanceConfigurationV2"] == nil)
        #expect(result.changes.map(\.key) == [.showOnClick])
        #expect(result.ignoredCount == 0)
    }

    @Test("The omission needs the key in the source; a plan without it names nothing")
    func noAppearanceNoOmission() {
        let result = plan(thawFixture(booleans: true), current: allOff)
        #expect(result.omissions.isEmpty)
    }

    @Test("The icon keys and the divider style are counted as ignored, never named or written")
    func iconAndDividerAreIgnored() {
        let result = plan(["IceIcon": Data([1]), "CustomIceIconIsTemplate": true, "SectionDividerStyle": 1], current: allOff)
        #expect(result.omissions.isEmpty)
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.ignoredCount == 3)
    }

    @Test("The appearance with everything else ignored: the omission is not part of the ignored count")
    func omissionIsNotIgnored() {
        let result = plan(thawFixture(booleans: false).merging(["MenuBarAppearanceConfigurationV2": Data([9])]) { first, _ in first }, current: allOff)
        #expect(result.omissions.count == 1)
        #expect(result.ignoredCount == 11)
    }

    @Test("A source whose every mapped value equals the current one gives no change, no write and no hotkey write")
    func everythingEqualGivesNothing() {
        let same = combination(4, 256)
        let current = allOff.merging(numbersNow) { first, _ in first }
        let result = plan(
            [
                "ShowOnClick": false,
                "ShowOnHover": false,
                "RehideInterval": 15,
                "RehideStrategy": 0,
                "Hotkeys": ["ToggleHiddenSection": same],
            ],
            current: current,
            hotkeys: ["ToggleHiddenSection": same]
        )
        #expect(result.changes.isEmpty)
        #expect(result.writes.isEmpty)
        #expect(result.omissions.isEmpty)
        #expect(result.ignoredCount == 0)
    }
}

@Suite("ImportBackupRecord")
struct ImportBackupRecordTests {
    private let ownBundle = "com.holzcloud.holzBar"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func record() -> ImportBackupRecord {
        ImportBackupRecord.make(
            source: .thaw,
            date: date,
            touchedKeys: ["ShowOnClick", "AutoRehide", "ShowOnHover"],
            domain: ["ShowOnClick": true, "AutoRehide": false, "UseIceBar": true, "NSWindow Frame X": "1 2 3 4"]
        )
    }

    @Test("make puts present touched keys into before and missing ones into absent")
    func makeSplitsPresentAndAbsent() {
        let made = record()
        #expect(made.before.keys.sorted() == ["AutoRehide", "ShowOnClick"])
        #expect(made.before["ShowOnClick"] as? Bool == true)
        #expect(made.before["AutoRehide"] as? Bool == false)
        #expect(made.absent == ["ShowOnHover"])
        #expect(made.source == .thaw)
        #expect(made.date == date)
    }

    @Test("The property list round-trips, also through serialized data")
    func propertyListRoundTrips() throws {
        let made = record()
        let direct = try #require(ImportBackupRecord(propertyList: made.propertyList()))
        #expect(direct.source == made.source)
        #expect(direct.date == made.date)
        #expect(direct.absent == made.absent)
        #expect(NSDictionary(dictionary: direct.before).isEqual(to: made.before))

        let data = try PropertyListSerialization.data(fromPropertyList: made.propertyList(), format: .binary, options: 0)
        let parsed = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let decoded = try #require(ImportBackupRecord(propertyList: parsed))
        #expect(decoded.source == .thaw)
        #expect(decoded.absent == ["ShowOnHover"])
        #expect(decoded.before["ShowOnClick"] as? Bool == true)
    }

    @Test("restoreWrites sets the before values and removes the absent keys")
    func restoreWrites() {
        let writes = record().restoreWrites(ownBundleIdentifier: ownBundle)
        #expect(writes.set.keys.sorted() == ["AutoRehide", "ShowOnClick"])
        #expect(writes.set["ShowOnClick"] as? Bool == true)
        #expect(writes.remove == ["ShowOnHover"])
    }

    @Test("A record with an unknown source or missing fields is refused")
    func unknownSourceIsRefused() {
        let valid = record().propertyList()
        var unknown = valid
        unknown["source"] = "someOtherApp"
        #expect(ImportBackupRecord(propertyList: unknown) == nil)
        for field in ["source", "date", "before", "absent"] {
            var broken = valid
            broken[field] = nil
            #expect(ImportBackupRecord(propertyList: broken) == nil, "a record without \(field) is refused")
        }
        var wrongKind = valid
        wrongKind["date"] = "yesterday"
        #expect(ImportBackupRecord(propertyList: wrongKind) == nil)
    }

    @Test("A key that is not holzBar's is dropped from set and from remove")
    func foreignKeysAreDropped() throws {
        var list = record().propertyList()
        list["before"] = ["ShowOnClick": true, "NSWindow Frame Settings": "1 2 3 4", "com.apple.dock": ["x": 1]] as [String: Any]
        list["absent"] = ["ShowOnHover", "NSStatusItem Preferred Position Item-0", "LastActiveProfileID"]
        let loaded = try #require(ImportBackupRecord(propertyList: list))
        let writes = loaded.restoreWrites(ownBundleIdentifier: ownBundle)
        #expect(writes.set.keys.sorted() == ["ShowOnClick"])
        #expect(writes.remove == ["ShowOnHover"])
        #expect(writes.remove.allSatisfy { Defaults.Key.importableKinds[$0] != nil })
    }

    @Test("A before value of the wrong kind is dropped when restoring")
    func wrongKindIsDropped() throws {
        var list = record().propertyList()
        list["before"] = ["ShowOnClick": "yes", "AutoRehide": true] as [String: Any]
        let loaded = try #require(ImportBackupRecord(propertyList: list))
        let writes = loaded.restoreWrites(ownBundleIdentifier: ownBundle)
        #expect(writes.set.keys.sorted() == ["AutoRehide"])
        #expect(writes.set["ShowOnClick"] == nil)
        #expect(!writes.remove.contains("ShowOnClick"))
    }

    @Test("A key that is both before and absent is set, never removed")
    func beforeWinsOverAbsent() throws {
        var list = record().propertyList()
        list["absent"] = ["ShowOnClick"]
        let loaded = try #require(ImportBackupRecord(propertyList: list))
        let writes = loaded.restoreWrites(ownBundleIdentifier: ownBundle)
        #expect(writes.set["ShowOnClick"] as? Bool == true)
        #expect(writes.remove.isEmpty)
    }
}
