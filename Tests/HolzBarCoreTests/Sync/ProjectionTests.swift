//
//  ProjectionTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncProjection")
struct ProjectionTests {
    private let table = SyncUnitTable.version1(normalizers: .canonical)

    private func hotkey(_ key: Int, _ modifiers: Int) -> Data {
        HotkeyStorage.encode(key: key, modifiers: modifiers)
    }

    // MARK: Tracer

    @Test("A setting and two hotkeys project to units; local keys never do")
    func tracerSnapshot() {
        let defaults: [String: Any] = [
            "ShowOnHover": true,
            "Hotkeys": [
                "ToggleHiddenSection": hotkey(4, 8),
                "OpenItem:com.example.app:Title": hotkey(5, 8),
            ],
            "ItemSections": ["com.example:Title": 1],
            "KnownItemTags": ["a"],
            "SettingsSyncDeviceID": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            "Unrelated": 1,
        ]
        let snapshot = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        #expect(snapshot[.whole("ShowOnHover")] == .bool(true))
        #expect(snapshot[.split(family: "Hotkeys", item: "ToggleHiddenSection")] == .data(hotkey(4, 8)))
        #expect(snapshot[.split(family: "Hotkeys", item: "OpenItem:com.example.app:Title")] == .data(hotkey(5, 8)))
        #expect(snapshot.count == 3)
    }

    @Test("A changed hotkey and a deleted one write only their items")
    func tracerWrites() {
        let defaults: [String: Any] = [
            "ShowOnHover": true,
            "Hotkeys": [
                "ToggleHiddenSection": hotkey(4, 8),
                "OpenItem:a": hotkey(5, 8),
                "OpenItem:b": hotkey(6, 8),
            ],
            "ItemSections": ["x": 1],
        ]
        let changes: [SyncUnitKey: SyncPayload] = [
            .split(family: "Hotkeys", item: "ToggleHiddenSection"): .value(.data(hotkey(7, 8))),
            .split(family: "Hotkeys", item: "OpenItem:a"): .deleted,
        ]
        let writes = SyncProjection.defaultsWrites(applying: changes, to: defaults, table: table)
        #expect(Set(writes.keys) == ["Hotkeys"])
        let hotkeys = writes["Hotkeys"] as? [String: Any]
        #expect(hotkeys?["ToggleHiddenSection"] as? Data == hotkey(7, 8))
        #expect(hotkeys?["OpenItem:a"] == nil)
        #expect(hotkeys?["OpenItem:b"] as? Data == hotkey(6, 8))
    }

    @Test("A whole unit writes its key and a deletion removes it")
    func wholeWrites() {
        let defaults: [String: Any] = ["ShowOnHover": false, "ShowOnClick": true]
        let writes = SyncProjection.defaultsWrites(
            applying: [.whole("ShowOnHover"): .value(.bool(true)), .whole("ShowOnClick"): .deleted],
            to: defaults,
            table: table
        )
        #expect(writes["ShowOnHover"] as? Bool == true)
        guard let removal = writes["ShowOnClick"] else {
            Issue.record("The deleted key is missing from the writes")
            return
        }
        #expect(removal == nil)
    }

    @Test("A hotkey this build cannot load is skipped, the others are applied")
    func invalidHotkeySkipped() {
        let defaults: [String: Any] = ["Hotkeys": ["OpenItem:b": hotkey(6, 8)]]
        let changes: [SyncUnitKey: SyncPayload] = [
            .split(family: "Hotkeys", item: "OpenItem:a"): .value(.data(hotkey(900, 8))),
            .split(family: "Hotkeys", item: "OpenItem:c"): .value(.data(hotkey(8, 8))),
            .split(family: "Hotkeys", item: "UnknownAction"): .value(.data(hotkey(9, 8))),
        ]
        let writes = SyncProjection.defaultsWrites(applying: changes, to: defaults, table: table)
        let hotkeys = writes["Hotkeys"] as? [String: Any]
        #expect(Set(hotkeys.map { Array($0.keys) } ?? []) == ["OpenItem:b", "OpenItem:c"])
    }

    @Test("A cleared hotkey stores null and still applies")
    func clearedHotkey() {
        let cleared = Data("null".utf8)
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "Hotkeys", item: "ToggleHiddenSection"): .value(.data(cleared))],
            to: [:],
            table: table
        )
        #expect((writes["Hotkeys"] as? [String: Any])?["ToggleHiddenSection"] as? Data == cleared)
    }

    @Test("A value that changes nothing writes nothing")
    func noChangeNoWrite() {
        let defaults: [String: Any] = ["Hotkeys": ["OpenItem:a": hotkey(5, 8)]]
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "Hotkeys", item: "OpenItem:a"): .value(.data(hotkey(5, 8)))],
            to: defaults,
            table: table
        )
        #expect(writes.isEmpty)
    }

    @Test("A present value of the wrong kind is still projected, so it can be kept local")
    func invalidValueIsProjected() throws {
        let snapshot = SyncProjection.snapshot(defaults: ["ShowOnHover": "yes"], table: table, generation: .g26)
        let value = try #require(snapshot[.whole("ShowOnHover")])
        let descriptor = try #require(table.descriptor(for: .whole("ShowOnHover")))
        #expect(!descriptor.validate(nil, value))
    }

    @Test("A number out of range is kept in range, as the models keep it")
    func numbersAreClamped() throws {
        let snapshot = SyncProjection.snapshot(defaults: ["RehideInterval": 100, "SpacerCount": 99], table: table, generation: .g26)
        #expect(snapshot[.whole("RehideInterval")] == .integer(30))
        // A whole number the rule refuses stays as it is and fails validation.
        let count = try #require(snapshot[.whole("SpacerCount")])
        #expect(!(table.descriptor(for: .whole("SpacerCount"))?.validate(nil, count) ?? true))
    }

    // MARK: Icon

    @Test("The icon image and its template flag are one unit")
    func iconUnit() throws {
        let image = Data([1, 2, 3])
        let defaults: [String: Any] = ["IceIcon": image, "CustomIceIconIsTemplate": true]
        let snapshot = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        let unit = SyncUnitKey.whole("HolzBarIcon")
        #expect(snapshot[unit] == .dictionary(["icon": .data(image), "template": .bool(true)]))
        #expect(snapshot[.whole("IceIcon")] == nil)
        #expect(snapshot[.whole("CustomIceIconIsTemplate")] == nil)

        let other = Data([9, 9])
        let writes = SyncProjection.defaultsWrites(
            applying: [unit: .value(.dictionary(["icon": .data(other), "template": .bool(false)]))],
            to: defaults,
            table: table
        )
        #expect(writes["IceIcon"] as? Data == other)
        #expect(writes["CustomIceIconIsTemplate"] as? Bool == false)

        let removal = SyncProjection.defaultsWrites(applying: [unit: .deleted], to: defaults, table: table)
        #expect(Set(removal.keys) == ["IceIcon", "CustomIceIconIsTemplate"])
    }

    @Test("An icon unit that is not an image and a flag is not applied")
    func invalidIconIsSkipped() {
        let writes = SyncProjection.defaultsWrites(
            applying: [.whole("HolzBarIcon"): .value(.dictionary(["icon": .string("x")]))],
            to: [:],
            table: table
        )
        #expect(writes.isEmpty)
    }

    // MARK: Item icons, reveal rules and marks

    @Test("Item icons project per item and apply per item")
    func itemIcons() {
        let defaults: [String: Any] = ["ItemIcons": ["a:Title": "app", "b:Title": "file:Custom_1.png", "c": "../etc/passwd"]]
        let snapshot = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        #expect(snapshot[.split(family: "ItemIcons", item: "a:Title")] == .string("app"))
        #expect(snapshot[.split(family: "ItemIcons", item: "b:Title")] == .string("file:Custom_1.png"))
        let changes: [SyncUnitKey: SyncPayload] = [
            .split(family: "ItemIcons", item: "a:Title"): .deleted,
            .split(family: "ItemIcons", item: "c"): .value(.string("file:../x.png")),
            .split(family: "ItemIcons", item: "d"): .value(.string("app")),
        ]
        let writes = SyncProjection.defaultsWrites(applying: changes, to: defaults, table: table)
        let icons = writes["ItemIcons"] as? [String: Any]
        #expect(Set(icons.map { Array($0.keys) } ?? []) == ["b:Title", "c", "d"])
        #expect(icons?["c"] as? String == "../etc/passwd")
    }

    @Test("Reveal rules sync per entry and only the entries this build knows")
    func revealRules() {
        let defaults: [String: Any] = ["RevealRules": ["LowBattery": true, "LowBatteryThreshold": 20, "Offline": false, "Future": 1]]
        let snapshot = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        #expect(snapshot[.split(family: "RevealRules", item: "LowBattery")] == .bool(true))
        #expect(snapshot[.split(family: "RevealRules", item: "LowBatteryThreshold")] == .integer(20))
        #expect(snapshot[.split(family: "RevealRules", item: "Offline")] == .bool(false))
        #expect(snapshot[.split(family: "RevealRules", item: "Future")] == nil)
        let writes = SyncProjection.defaultsWrites(
            applying: [
                .split(family: "RevealRules", item: "LowBatteryThreshold"): .value(.integer(35)),
                .split(family: "RevealRules", item: "Offline"): .value(.integer(1)),
            ],
            to: defaults,
            table: table
        )
        let rules = writes["RevealRules"] as? [String: Any]
        #expect((rules?["LowBatteryThreshold"] as? NSNumber)?.intValue == 35)
        #expect(rules?["Offline"] as? Bool == false)
        #expect(rules?["Future"] as? Int == 1)
    }

    @Test("A marked item is true; applying a deletion unmarks it and applying true marks it once")
    func marks() {
        let defaults: [String: Any] = ["RevealOnChangeItems": ["b", "a"]]
        let snapshot = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        #expect(snapshot[.split(family: "RevealOnChangeItems", item: "a")] == .bool(true))
        #expect(snapshot[.split(family: "RevealOnChangeItems", item: "b")] == .bool(true))
        #expect(snapshot[.split(family: "RevealOnChangeItems", item: "c")] == nil)

        let writes = SyncProjection.defaultsWrites(
            applying: [
                .split(family: "RevealOnChangeItems", item: "a"): .deleted,
                .split(family: "RevealOnChangeItems", item: "c"): .value(.bool(true)),
                .split(family: "RevealOnChangeItems", item: "b"): .value(.bool(true)),
            ],
            to: defaults,
            table: table
        )
        #expect(writes["RevealOnChangeItems"] as? [String] == ["b", "c"])

        let again = SyncProjection.defaultsWrites(
            applying: [.split(family: "RevealOnChangeItems", item: "c"): .value(.bool(true))],
            to: ["RevealOnChangeItems": ["b", "c"]],
            table: table
        )
        #expect(again.isEmpty)
    }

    // MARK: l27

    @Test("l27 projects the stored sections on macOS 27 and nothing on macOS 26")
    func layout27Snapshot() {
        let defaults: [String: Any] = ["MacOS27Layout": ["com.a": 1, "com.c": 2]]
        let g27 = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g27)
        #expect(g27[.split(family: "l27", item: "com.a")] == .integer(1))
        #expect(g27[.split(family: "l27", item: "com.c")] == .integer(2))
        let g26 = SyncProjection.snapshot(defaults: defaults, table: table, generation: .g26)
        #expect(g26.isEmpty)
    }

    @Test("An application without a stored section is visible, which is the value 0")
    func layout27LocalValue() {
        let snapshot = SyncProjection.snapshot(defaults: ["MacOS27Layout": ["com.a": 1]], table: table, generation: .g27)
        #expect(SyncProjection.localValue(.split(family: "l27", item: "com.a"), in: snapshot, table: table) == .integer(1))
        #expect(SyncProjection.localValue(.split(family: "l27", item: "com.b"), in: snapshot, table: table) == .integer(0))
        #expect(SyncProjection.localValue(.split(family: "Hotkeys", item: "OpenItem:a"), in: snapshot, table: table) == nil)
        #expect(SyncProjection.localValue(.whole("ShowOnHover"), in: snapshot, table: table) == nil)
    }

    @Test("Applying l27 removes visible applications and sets the others")
    func layout27Writes() {
        let defaults: [String: Any] = ["MacOS27Layout": ["com.a": 1, "com.keep": 2]]
        let writes = SyncProjection.defaultsWrites(
            applying: [
                .split(family: "l27", item: "com.a"): .value(.integer(0)),
                .split(family: "l27", item: "com.new"): .value(.integer(2)),
                .split(family: "l27", item: "com.bad"): .value(.integer(3)),
            ],
            to: defaults,
            table: table
        )
        let layout = writes["MacOS27Layout"] as? [String: Any]
        #expect(Set(layout.map { Array($0.keys) } ?? []) == ["com.keep", "com.new"])
        #expect(layout?["com.new"] as? Int == 2)
        #expect(layout?["com.keep"] as? Int == 2)
    }

    @Test("Applying visible to an application that has no entry writes nothing")
    func layout27VisibleNoOp() {
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "l27", item: "com.b"): .value(.integer(0))],
            to: ["MacOS27Layout": ["com.a": 1]],
            table: table
        )
        #expect(writes.isEmpty)
    }

    // MARK: prof

    private func profilesData(_ profiles: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys])
    }

    private func decodedProfiles(_ write: Any??) throws -> [[String: Any]] {
        let data = try #require(write as? Data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("A profile projects its name and its macOS 27 part only")
    func profileSnapshot() throws {
        let stored = try profilesData([
            [
                "profileID": "P1", "name": "Work", "itemSections": ["x:y": 1], "applicationSections": ["com.a": 2],
                "knownApplications": ["com.b", "com.a", "com.b"], "displayUUID": "D", "spaceUUID": "S", "future": 1,
            ],
            ["profileID": "P2", "name": "Home", "itemSections": [String: Int](), "applicationSections": [String: Int]()],
        ])
        let g27 = SyncProjection.snapshot(defaults: ["LayoutProfiles": stored], table: table, generation: .g27)
        #expect(g27[.split(family: "prof", item: "P1")] == .dictionary([
            "name": .string("Work"),
            "applicationSections": .dictionary(["com.a": .integer(2)]),
            "knownApplications": .array([.string("com.a"), .string("com.b")]),
        ]))
        #expect(g27[.split(family: "prof", item: "P2")] == .dictionary([
            "name": .string("Home"),
            "applicationSections": .dictionary([:]),
        ]))
        let g26 = SyncProjection.snapshot(defaults: ["LayoutProfiles": stored], table: table, generation: .g26)
        #expect(g26.isEmpty)
    }

    @Test("Applying a profile keeps the macOS 26 part, the bindings and unknown fields")
    func profileApply() throws {
        let stored = try profilesData([
            [
                "profileID": "P1", "name": "Work", "itemSections": ["x:y": 1], "applicationSections": ["com.a": 2],
                "knownApplications": ["com.a"], "displayUUID": "D", "spaceUUID": "S", "future": 1,
            ],
        ])
        let payload = SyncValue.dictionary([
            "name": .string("Office"),
            "applicationSections": .dictionary(["com.z": .integer(1)]),
            "knownApplications": .array([.string("com.z")]),
        ])
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "prof", item: "P1"): .value(payload)],
            to: ["LayoutProfiles": stored],
            table: table
        )
        let profiles = try decodedProfiles(writes["LayoutProfiles"])
        #expect(profiles.count == 1)
        let profile = profiles[0]
        #expect(profile["name"] as? String == "Office")
        #expect(profile["applicationSections"] as? [String: Int] == ["com.z": 1])
        #expect(profile["knownApplications"] as? [String] == ["com.z"])
        #expect(profile["itemSections"] as? [String: Int] == ["x:y": 1])
        #expect(profile["displayUUID"] as? String == "D")
        #expect(profile["spaceUUID"] as? String == "S")
        #expect(profile["future"] as? Int == 1)
        #expect(profile["profileID"] as? String == "P1")
    }

    @Test("A profile without known applications loses that field")
    func profileWithoutKnownApplications() throws {
        let stored = try profilesData([
            ["profileID": "P1", "name": "Work", "itemSections": [String: Int](), "applicationSections": [String: Int](), "knownApplications": ["a"]],
        ])
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "prof", item: "P1"): .value(.dictionary(["name": .string("Work"), "applicationSections": .dictionary([:])]))],
            to: ["LayoutProfiles": stored],
            table: table
        )
        let profiles = try decodedProfiles(writes["LayoutProfiles"])
        #expect(profiles[0]["knownApplications"] == nil)
    }

    @Test("A deletion removes only that profile and an unknown ID appends a profile")
    func profileDeleteAndAppend() throws {
        let stored = try profilesData([
            ["profileID": "P1", "name": "Work", "itemSections": ["k": 1], "applicationSections": [String: Int]()],
            ["profileID": "P2", "name": "Home", "itemSections": ["k": 2], "applicationSections": [String: Int]()],
        ])
        let deleted = SyncProjection.defaultsWrites(applying: [.split(family: "prof", item: "P1"): .deleted], to: ["LayoutProfiles": stored], table: table)
        let remaining = try decodedProfiles(deleted["LayoutProfiles"])
        #expect(remaining.map { $0["profileID"] as? String } == ["P2"])
        #expect(remaining[0]["itemSections"] as? [String: Int] == ["k": 2])

        let appended = SyncProjection.defaultsWrites(
            applying: [.split(family: "prof", item: "P3"): .value(.dictionary(["name": .string("Away"), "applicationSections": .dictionary(["com.a": .integer(1)])]))],
            to: ["LayoutProfiles": stored],
            table: table
        )
        let profiles = try decodedProfiles(appended["LayoutProfiles"])
        #expect(profiles.map { $0["name"] as? String } == ["Away", "Home", "Work"])
        let added = try #require(profiles.first { $0["profileID"] as? String == "P3" })
        #expect(added["itemSections"] as? [String: Int] == [:])
        #expect(added["displayUUID"] == nil)
        #expect(added["spaceUUID"] == nil)
        #expect(added["applicationSections"] as? [String: Int] == ["com.a": 1])
    }

    @Test("A profile with a bad name or a bad section is not written")
    func profileValidation() throws {
        let stored = try profilesData([["profileID": "P1", "name": "Work", "itemSections": [String: Int](), "applicationSections": [String: Int]()]])
        let cases: [SyncValue] = [
            .dictionary(["name": .string(""), "applicationSections": .dictionary([:])]),
            .dictionary(["name": .string(String(repeating: "x", count: 201)), "applicationSections": .dictionary([:])]),
            .dictionary(["name": .string("A"), "applicationSections": .dictionary(["com.a": .integer(3)])]),
            .dictionary(["name": .string("A"), "applicationSections": .dictionary(["com.a": .string("1")])]),
            .dictionary(["name": .string("A"), "applicationSections": .dictionary([:]), "extra": .bool(true)]),
            .dictionary(["name": .string("A")]),
            .string("A"),
        ]
        for value in cases {
            let writes = SyncProjection.defaultsWrites(applying: [.split(family: "prof", item: "P1"): .value(value)], to: ["LayoutProfiles": stored], table: table)
            #expect(writes.isEmpty)
        }
        let longName = SyncValue.dictionary(["name": .string(String(repeating: "x", count: 200)), "applicationSections": .dictionary([:])])
        let accepted = SyncProjection.defaultsWrites(applying: [.split(family: "prof", item: "P1"): .value(longName)], to: ["LayoutProfiles": stored], table: table)
        #expect(!accepted.isEmpty)
    }

    @Test("Stored profiles that are not JSON are left alone")
    func profileGarbage() {
        let writes = SyncProjection.defaultsWrites(
            applying: [.split(family: "prof", item: "P1"): .value(.dictionary(["name": .string("A"), "applicationSections": .dictionary([:])]))],
            to: ["LayoutProfiles": Data("garbage".utf8)],
            table: table
        )
        #expect(writes.isEmpty)
    }

    // MARK: known27

    @Test("The union keeps a sorted array without duplicates and never removes an element")
    func knownUnion() {
        let defaults: [String: Any] = ["KnownApplications27": ["com.b", "com.a"]]
        let writes = SyncProjection.knownApplicationsUnion(["com.c", "com.a", "com.d"], into: defaults)
        #expect(writes["KnownApplications27"] as? [String] == ["com.a", "com.b", "com.c", "com.d"])
        #expect(SyncProjection.knownApplicationsUnion(["com.a"], into: defaults).isEmpty)
        #expect(SyncProjection.knownApplicationsUnion([], into: defaults).isEmpty)
        let fresh = SyncProjection.knownApplicationsUnion(["z", "y"], into: [:])
        #expect(fresh["KnownApplications27"] as? [String] == ["y", "z"])
        #expect(SyncProjection.knownApplications(in: defaults) == ["com.a", "com.b"])
    }

    // MARK: Legacy

    @Test("Settings of the legacy file map to settings units only")
    func legacySettings() {
        let settings: [String: SyncValue] = [
            "ShowOnHover": .bool(true),
            "RehideInterval": .real(7),
            "IceIcon": .data(Data([1])),
            "CustomIceIconIsTemplate": .bool(false),
            "Hotkeys": .dictionary([
                "ToggleHiddenSection": .data(hotkey(4, 8)),
                "ApplyProfile:Work": .data(hotkey(5, 8)),
                "OpenItem:a": .data(hotkey(6, 8)),
            ]),
            "MacOS27Layout": .dictionary(["com.a": .integer(1)]),
            "ItemSections": .dictionary(["x": .integer(1)]),
            "LayoutProfiles": .data(Data("[]".utf8)),
            "KnownItemTags": .array([.string("a")]),
            "KnownApplications27": .array([.string("a")]),
            "MacOS27LayoutSeeded": .bool(true),
            "hasMigrated0_8_0": .bool(true),
            "SettingsSyncDeviceID": .string("X"),
        ]
        let units = SyncProjection.units(fromLegacySettings: settings, table: table)
        #expect(Set(units.keys) == [
            .whole("ShowOnHover"),
            .whole("RehideInterval"),
            .whole("HolzBarIcon"),
            .split(family: "Hotkeys", item: "ToggleHiddenSection"),
            .split(family: "Hotkeys", item: "OpenItem:a"),
        ])
        #expect(units[.whole("HolzBarIcon")] == .dictionary(["icon": .data(Data([1])), "template": .bool(false)]))
    }

    @Test("A local key is never written, whatever the changes say")
    func localKeysAreNeverWritten() {
        let hostile: [SyncUnitKey: SyncPayload] = [
            .whole("ItemSections"): .value(.dictionary([:])),
            .whole("SettingsSyncDeviceID"): .value(.string("X")),
            .whole("KnownItemTags"): .value(.array([])),
            .whole("hasMigrated0_8_0"): .value(.bool(true)),
            .whole("known27"): .value(.array([.string("a")])),
        ]
        #expect(SyncProjection.defaultsWrites(applying: hostile, to: [:], table: table).isEmpty)
    }
}
