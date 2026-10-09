//
//  DefaultsStoreTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncDefaultsStore")
struct DefaultsStoreTests {
    private let table = SyncUnitTable.version1(normalizers: .canonical)

    private func hotkey(_ key: Int, _ modifiers: Int) -> Data {
        HotkeyStorage.encode(key: key, modifiers: modifiers)
    }

    /// A fresh preferences suite that is removed when the body ends.
    private func withStore(_ body: (UserDefaults, SyncDefaultsStore) throws -> Void) throws {
        let name = "holzBar.tests.DefaultsStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, SyncDefaultsStore(defaults: defaults, domainName: name))
    }

    // MARK: Tracer

    @Test("A setting, two hotkeys and a re-keyed icon become a snapshot of the synced units only")
    func tracerSnapshot() throws {
        try withStore { defaults, store in
            defaults.set(true, forKey: "ShowOnHover")
            defaults.set(
                ["ToggleHiddenSection": hotkey(4, 8), "OpenItem:ns:Title": hotkey(5, 8)],
                forKey: "Hotkeys"
            )
            defaults.set(["ns:Title": "app"], forKey: "ItemIcons")
            defaults.set(["ns"], forKey: "TitleChangingItemOwners")
            defaults.set(["ns:Title": 1], forKey: "ItemSections")
            defaults.set(["tag"], forKey: "KnownItemTags")
            defaults.set("3F2504E0-4F89-11D3-9A0C-0305E82C3301", forKey: "SettingsSyncDeviceID")
            defaults.set(Data([1, 2, 3]), forKey: "NSWindow Frame Settings")
            let snapshot = store.snapshot(table: table, generation: .g26, baselineKeys: [])
            #expect(Set(snapshot.values.keys) == [
                .whole("ShowOnHover"),
                .split(family: "Hotkeys", item: "ToggleHiddenSection"),
                .split(family: "Hotkeys", item: "OpenItem:ns:Title"),
                .split(family: "ItemIcons", item: "ns:Title"),
            ])
            #expect(snapshot.values[.whole("ShowOnHover")] == .bool(true))
            #expect(snapshot.aliased == [
                .split(family: "Hotkeys", item: "OpenItem:ns:Title"),
                .split(family: "ItemIcons", item: "ns:Title"),
            ])
            #expect(snapshot.known27.isEmpty)
        }
    }

    @Test("A unit payload changes only its own key")
    func applyChangesOnlyItsKey() throws {
        try withStore { defaults, store in
            defaults.set(true, forKey: "ShowOnHover")
            defaults.set(false, forKey: "ShowOnClick")
            defaults.set(["ItemSections-like": 1], forKey: "ItemSections")
            let report = store.apply([.whole("ShowOnHover"): .value(.bool(false))], table: table)
            #expect(report.applied == [.whole("ShowOnHover")])
            #expect(report.skipped.isEmpty)
            #expect(defaults.object(forKey: "ShowOnHover") as? Bool == false)
            #expect(defaults.object(forKey: "ShowOnClick") as? Bool == false)
            #expect(defaults.dictionary(forKey: "ItemSections")?["ItemSections-like"] as? Int == 1)
        }
    }

    // MARK: Snapshot

    @Test("A key that only the baseline holds and this Mac maps to another key is aliased")
    func baselineOnlyKeyIsAliased() throws {
        try withStore { defaults, store in
            defaults.set(["ns"], forKey: "TitleChangingItemOwners")
            let old = SyncUnitKey.split(family: "ItemIcons", item: "ns:Title")
            let other = SyncUnitKey.split(family: "ItemIcons", item: "other:Title")
            let snapshot = store.snapshot(table: table, generation: .g26, baselineKeys: [old, other, .whole("ShowOnHover")])
            #expect(snapshot.values.isEmpty)
            #expect(snapshot.aliased == [old])
        }
    }

    @Test("Window frames and every SettingsSync key never reach a snapshot")
    func excludedKeysNeverAppear() throws {
        try withStore { defaults, store in
            defaults.set(Data([1]), forKey: "NSWindow Frame Settings")
            defaults.set(Date(), forKey: "SettingsSyncLastSynced")
            defaults.set(5, forKey: "SettingsSyncGeneration")
            defaults.set(true, forKey: "SUEnableAutomaticChecks")
            defaults.set(1, forKey: "NSStatusItem Preferred Position holzBar")
            let snapshot = store.snapshot(table: table, generation: .g27, baselineKeys: [])
            #expect(snapshot.values.isEmpty)
            #expect(snapshot.aliased.isEmpty)
        }
    }

    @Test("The known applications are read on macOS 27 only")
    func knownApplicationsOnlyOn27() throws {
        try withStore { defaults, store in
            defaults.set(["b:App", "a:App", "a:App"], forKey: "KnownApplications27")
            #expect(store.snapshot(table: table, generation: .g26, baselineKeys: []).known27.isEmpty)
            #expect(store.snapshot(table: table, generation: .g27, baselineKeys: []).known27 == ["a:App", "b:App"])
        }
    }

    // MARK: Apply

    @Test("A deletion payload removes only its item")
    func deletionRemovesOnlyItsItem() throws {
        try withStore { defaults, store in
            defaults.set(["a:Title": "app", "b:Title": "app"], forKey: "ItemIcons")
            let report = store.apply([.split(family: "ItemIcons", item: "a:Title"): .deleted], table: table)
            #expect(report.applied == [.split(family: "ItemIcons", item: "a:Title")])
            #expect(defaults.dictionary(forKey: "ItemIcons") as? [String: String] == ["b:Title": "app"])
        }
    }

    @Test("A deleted whole unit removes its key")
    func deletedWholeUnit() throws {
        try withStore { defaults, store in
            defaults.set(true, forKey: "ShowOnHover")
            store.apply([.whole("ShowOnHover"): .deleted], table: table)
            #expect(defaults.object(forKey: "ShowOnHover") == nil)
        }
    }

    @Test("An invalid payload is skipped and reported, the valid ones are written")
    func invalidPayloadIsSkipped() throws {
        try withStore { defaults, store in
            defaults.set(1, forKey: "ShowOnClick")
            let invalid = SyncUnitKey.whole("ShowOnHover")
            let valid = SyncUnitKey.whole("ShowOnClick")
            let report = store.apply([invalid: .value(.string("yes")), valid: .value(.bool(true))], table: table)
            #expect(report.skipped == [invalid])
            #expect(report.applied == [valid])
            #expect(defaults.object(forKey: "ShowOnHover") == nil)
            #expect(defaults.object(forKey: "ShowOnClick") as? Bool == true)
        }
    }

    @Test("A unit this build does not know is skipped; a local key has no unit to apply")
    func unknownAndLocalUnits() throws {
        try withStore { defaults, store in
            let units: [SyncUnitKey: SyncPayload] = [
                .whole("FutureSetting"): .value(.bool(true)),
                .whole("ItemSections"): .value(.bool(true)),
                .whole("SettingsSyncLastSynced"): .deleted,
                .whole("SettingsSyncDeviceID"): .value(.string("x")),
            ]
            let report = store.apply(units, table: table)
            #expect(report.applied.isEmpty)
            #expect(report.skipped == Set(units.keys))
            for key in ["FutureSetting", "ItemSections", "SettingsSyncLastSynced", "SettingsSyncDeviceID"] {
                #expect(defaults.object(forKey: key) == nil, "\(key)")
            }
        }
    }

    @Test("Applying the value a key already holds changes nothing and counts as applied")
    func applyingTheSameValue() throws {
        try withStore { defaults, store in
            defaults.set(true, forKey: "ShowOnHover")
            let report = store.apply([.whole("ShowOnHover"): .value(.bool(true))], table: table)
            #expect(report.applied == [.whole("ShowOnHover")])
            #expect(defaults.object(forKey: "ShowOnHover") as? Bool == true)
        }
    }

    @Test("Known applications are added and never lost")
    func knownApplicationsUnion() throws {
        try withStore { defaults, store in
            defaults.set(["a:App"], forKey: "KnownApplications27")
            store.applyKnownApplications(["b:App", "a:App"])
            #expect(defaults.stringArray(forKey: "KnownApplications27") == ["a:App", "b:App"])
            store.applyKnownApplications([])
            #expect(defaults.stringArray(forKey: "KnownApplications27") == ["a:App", "b:App"])
        }
    }

    // MARK: Sync state keys

    @Test("The generation and the counter mirror round-trip")
    func generationAndMirror() throws {
        try withStore { defaults, store in
            #expect(store.generation == nil)
            #expect(store.counterMirror == 0)
            store.setGeneration(7)
            store.setCounterMirror(UInt64(UInt32.max) + 5)
            store.flush()
            #expect(store.generation == 7)
            #expect(store.counterMirror == UInt64(UInt32.max) + 5)
            #expect(defaults.object(forKey: "SettingsSyncGeneration") != nil)
        }
    }

    @Test("lastSyncedSeen reads a date set directly and the store never writes it")
    func lastSyncedIsReadOnly() throws {
        try withStore { defaults, store in
            #expect(store.lastSyncedSeen == nil)
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            defaults.set(date, forKey: "SettingsSyncLastSynced")
            store.setGeneration(1)
            store.setCounterMirror(2)
            store.apply([.whole("ShowOnHover"): .value(.bool(true))], table: table)
            store.applyKnownApplications(["a:App"])
            store.flush()
            #expect(store.lastSyncedSeen == date)
        }
    }
}
