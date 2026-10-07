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
}
