import Foundation
import Testing
@testable import HolzBarCore

@Suite("LegacySettingsMigration")
struct LegacySettingsMigrationTests {
    /// Every migration flag set, as in the settings of a current Ice.
    private var allFlags: [String: Any] {
        Dictionary(uniqueKeysWithValues: LegacySettingsMigration.migrationFlags.map { ($0, true as Any) })
    }

    /// The old sections as Ice stored them before 0.8.0.
    private func sectionsData(_ sections: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: sections)
    }

    @Test("Settings already migrated stay as they are")
    func alreadyMigratedStays() {
        var settings = allFlags
        settings["SectionDividerStyle"] = 1
        settings["UseIceBar"] = true
        settings["Hotkeys"] = ["SearchMenuBarItems": HotkeyStorage.encode(key: 3, modifiers: 4)]
        let migrated = LegacySettingsMigration.migrate(settings)
        #expect(NSDictionary(dictionary: migrated).isEqual(NSDictionary(dictionary: settings)))
    }

    @Test("Hotkeys move out of the old sections")
    func hotkeysMoveOutOfSections() throws {
        let sections = try sectionsData([
            ["name": "Visible"],
            ["name": "Hidden", "hotkey": ["key": 49, "modifiers": 10]],
        ])
        let settings: [String: Any] = [
            "Sections": sections,
            "Hotkeys": ["SearchMenuBarItems": HotkeyStorage.encode(key: 3, modifiers: 4)],
        ]
        let migrated = LegacySettingsMigration.migrate(settings)
        let hotkeys = try #require(migrated["Hotkeys"] as? [String: Any])
        let hidden = try #require(hotkeys["ToggleHiddenSection"] as? Data)
        #expect(String(decoding: hidden, as: UTF8.self) == "[49,10]")
        #expect(hotkeys["SearchMenuBarItems"] as? Data == HotkeyStorage.encode(key: 3, modifiers: 4))
        #expect(hotkeys["ToggleAlwaysHiddenSection"] == nil)
    }

    @Test("The old sections are dropped")
    func sectionsAreDropped() throws {
        let sections = try sectionsData([["name": "Always Hidden", "hotkey": ["key": 1, "modifiers": 2]]])
        let settings: [String: Any] = ["Sections": sections]
        let migrated = LegacySettingsMigration.migrate(settings)
        #expect(migrated["Sections"] == nil)
        let hotkeys = try #require(migrated["Hotkeys"] as? [String: Any])
        #expect(hotkeys["ToggleAlwaysHiddenSection"] as? Data == HotkeyStorage.encode(key: 1, modifiers: 2))
    }

    @Test("Section dividers become a divider style")
    func sectionDividersBecomeStyle() {
        let shown = LegacySettingsMigration.migrate(["ShowSectionDividers": true])
        #expect(shown["SectionDividerStyle"] as? Int == 1)
        #expect(shown["ShowSectionDividers"] == nil)

        let hidden = LegacySettingsMigration.migrate(["ShowSectionDividers": false])
        #expect(hidden["SectionDividerStyle"] as? Int == 0)
        #expect(hidden["ShowSectionDividers"] == nil)

        let absent = LegacySettingsMigration.migrate([:])
        #expect(absent["SectionDividerStyle"] as? Int == 0)
    }

    @Test("Status item positions are not carried over")
    func statusItemPositionsDropped() {
        let settings: [String: Any] = [
            "NSStatusItem Preferred Position HItem": 120.0,
            "NSStatusItem Visible SItem": true,
            "UseIceBar": true,
        ]
        let migrated = LegacySettingsMigration.migrate(settings)
        #expect(!migrated.keys.contains { $0.hasPrefix("NSStatusItem") })
        #expect(migrated["UseIceBar"] as? Bool == true)
    }

    @Test("Corrupt old sections are ignored")
    func corruptSectionsIgnored() throws {
        let hotkeys: [String: Any] = ["SearchMenuBarItems": HotkeyStorage.encode(key: 3, modifiers: 4)]
        for corrupt in [Data("not json".utf8), Data("{\"name\": \"Hidden\"}".utf8), Data("[1, 2]".utf8)] {
            let migrated = LegacySettingsMigration.migrate(["Sections": corrupt, "Hotkeys": hotkeys])
            #expect(migrated["Sections"] == nil)
            let migratedHotkeys = try #require(migrated["Hotkeys"] as? [String: Any])
            #expect(NSDictionary(dictionary: migratedHotkeys).isEqual(NSDictionary(dictionary: hotkeys)))
        }
    }

    @Test("Every step is marked done")
    func everyStepMarkedDone() {
        let migrated = LegacySettingsMigration.migrate(["hasMigrated0_8_0": true])
        #expect(LegacySettingsMigration.migrationFlags.count == 6)
        for flag in LegacySettingsMigration.migrationFlags {
            #expect(migrated[flag] as? Bool == true, "\(flag) is not set")
        }
    }

    @Test("Only an unconverted old appearance needs converting")
    func appearanceConversion() {
        let data = Data("{}".utf8)
        #expect(LegacySettingsMigration.needsAppearanceConversion(["MenuBarAppearanceConfiguration": data]))
        #expect(!LegacySettingsMigration.needsAppearanceConversion([
            "MenuBarAppearanceConfiguration": data,
            "hasMigrated0_11_10": true,
        ]))
        #expect(!LegacySettingsMigration.needsAppearanceConversion([:]))
    }
}
