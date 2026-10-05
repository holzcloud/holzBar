import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSchema")
struct SettingsSchemaTests {
    @Test("Unknown keys are ignored")
    func unknownKeysAreIgnored() {
        let result = SettingsSchema.validated(
            ["ShowOnHover": true, "NSQuitAlwaysKeepsWindows": true],
            kinds: ["ShowOnHover": .bool]
        )
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["NSQuitAlwaysKeepsWindows"])
    }

    @Test("A value of the wrong type is ignored")
    func wrongTypeIsIgnored() {
        let result = SettingsSchema.validated(["ShowOnHover": "yes"], kinds: ["ShowOnHover": .bool])
        #expect(result.accepted.isEmpty)
        #expect(result.ignored == ["ShowOnHover"])
    }

    @Test("Booleans and numbers are told apart")
    func booleansAndNumbersAreToldApart() {
        let kinds: [String: SettingsSchema.Kind] = [
            "Number": .number,
            "Bool": .bool,
            "Integer": .number,
            "Double": .number,
            "Flag": .bool,
        ]
        let result = SettingsSchema.validated(
            [
                "Number": true,
                "Bool": 3,
                "Integer": 3,
                "Double": 0.25,
                "Flag": true,
            ],
            kinds: kinds
        )
        #expect(result.ignored == ["Bool", "Number"])
        #expect(result.accepted.keys.sorted() == ["Double", "Flag", "Integer"])
    }

    @Test("Values read from a property list keep their kinds")
    func propertyListValuesKeepTheirKinds() throws {
        let settings: [String: Any] = [
            "Bool": true,
            "Integer": 42,
            "Double": 1.5,
            "String": "Work",
            "Data": Data([1, 2, 3]),
            "Date": Date(timeIntervalSinceReferenceDate: 0),
            "StringArray": ["a", "b"],
            "Dictionary": ["key": 1],
        ]
        let kinds: [String: SettingsSchema.Kind] = [
            "Bool": .bool,
            "Integer": .number,
            "Double": .number,
            "String": .string,
            "Data": .data,
            "Date": .date,
            "StringArray": .stringArray,
            "Dictionary": .dictionary,
        ]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: settings, format: format, options: 0)
            let read = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let result = SettingsSchema.validated(read, kinds: kinds)
            #expect(result.ignored.isEmpty)
            #expect(result.accepted.keys.sorted() == settings.keys.sorted())
        }
    }

    @Test("A string array with another element is ignored")
    func stringArrayWithAnotherElementIsIgnored() {
        let mixed: [Any] = ["a", 1]
        let result = SettingsSchema.validated(["KnownItemTags": mixed], kinds: ["KnownItemTags": .stringArray])
        #expect(result.accepted.isEmpty)
        #expect(result.ignored == ["KnownItemTags"])
    }

    @Test("Every stored key but the local ones is importable")
    func everyStoredKeyIsImportable() {
        let importable = Defaults.Key.allCases.filter { !Defaults.Key.localOnlyKeys.contains($0) }
        let rawValues = importable.map(\.rawValue)
        #expect(Defaults.Key.importableKinds.count == rawValues.count)
        #expect(Set(Defaults.Key.importableKinds.keys) == Set(rawValues))
        for key in importable {
            #expect(Defaults.Key.importableKinds[key.rawValue] == key.settingsKind)
        }
    }

    @Test("A settings file cannot turn settings sync on")
    func settingsFileCannotTurnSyncOn() {
        #expect(Defaults.Key.localOnlyKeys.contains(.syncsSettingsWithICloud))
        #expect(Defaults.Key.importableKinds["SyncsSettingsWithICloud"] == nil)
        let result = Defaults.Key.validatedSettings(["SyncsSettingsWithICloud": true, "ShowOnHover": true])
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["SyncsSettingsWithICloud"])
    }

    @Test("Numbers out of range are clamped, and infinity and NaN refused")
    func numbersAreClamped() {
        let result = Defaults.Key.validatedSettings([
            "ItemSpacingOffset": 1e300,
            "RehideInterval": -5.0,
            "ShowOnHoverDelay": Double.nan,
            "TempShowInterval": Double.infinity,
            "SpacerWidth": 30.0,
        ])
        #expect((result.accepted["ItemSpacingOffset"] as? Double) == 16)
        #expect((result.accepted["RehideInterval"] as? Double) == 0)
        #expect((result.accepted["SpacerWidth"] as? Double) == 30)
        #expect(result.ignored == ["ShowOnHoverDelay", "TempShowInterval"])
    }

    @Test("Whole numbers outside their range or with a fraction are refused")
    func wholeNumbersAreChecked() {
        let result = Defaults.Key.validatedSettings([
            "SpacerCount": 1e300,
            "IceBarLocation": 1.5,
            "RehideStrategy": -1,
            "NewItemsPlacement": 2,
            "SectionDividerStyle": 1.0,
        ])
        #expect(result.accepted.keys.sorted() == ["NewItemsPlacement", "SectionDividerStyle"])
        #expect(result.ignored == ["IceBarLocation", "RehideStrategy", "SpacerCount"])
    }

    @Test("A number without a rule must still be finite")
    func numberWithoutRuleMustBeFinite() {
        let result = SettingsSchema.validated(
            ["Finite": 12.5, "Infinite": -Double.infinity],
            kinds: ["Finite": .number, "Infinite": .number]
        )
        #expect(result.accepted.keys.sorted() == ["Finite"])
        #expect(result.ignored == ["Infinite"])
    }

    @Test("Every numeric setting has a rule")
    func everyNumericSettingHasARule() {
        for key in Defaults.Key.allCases where key.settingsKind == .number {
            #expect(key.numberRule != nil, "\(key.rawValue) has no range")
        }
        for key in Defaults.Key.allCases where key.settingsKind != .number {
            #expect(key.numberRule == nil)
        }
    }

    @Test("Stored numbers are clamped when they are read")
    func storedNumbersAreClamped() {
        #expect(Defaults.Key.itemSpacingOffset.clamped(1e300, fallback: 0) == 16)
        #expect(Defaults.Key.itemSpacingOffset.clamped(-1e300, fallback: 0) == -16)
        #expect(Defaults.Key.itemSpacingOffset.clamped(.nan, fallback: 4) == 4)
        #expect(Defaults.Key.tempShowInterval.clamped(60, fallback: 15) == 30)
        #expect(Defaults.Key.showOnHoverDelay.clamped(.infinity, fallback: 0.2) == 0.2)
        #expect(Defaults.Key.rehideInterval.clamped(12, fallback: 15) == 12)
    }

    @Test("Stored key names never change")
    func storedKeyNamesNeverChange() {
        // Renaming a stored key would lose every user's setting and break the import of
        // Ice's settings.
        #expect(Defaults.Key.showHolzBarIcon.rawValue == "ShowIceIcon")
        #expect(Defaults.Key.useShelf.rawValue == "UseIceBar")
        #expect(Defaults.Key.hasImportedPreviousSettings.rawValue == "HasImportedIceSettings")
        #expect(Defaults.Key.macOS27ShelfWaitsForRefresh.rawValue == "MacOS27IceBarWaitsForRefresh")
        #expect(Defaults.Key.hotkeys.rawValue == "Hotkeys")
        #expect(Defaults.Key.menuBarAppearanceConfigurationV2.rawValue == "MenuBarAppearanceConfigurationV2")
    }

    @Test("Sync keeps the settings the other Mac lacks")
    func syncKeepsMissingKeys() {
        let removed = Defaults.Key.keysRemoved(
            applying: ["A": 1],
            over: ["A": 0, "B": 1],
            removesMissingKeys: false
        )
        #expect(removed.isEmpty)
    }

    @Test("A file import removes the settings the file lacks")
    func importRemovesMissingKeys() {
        let removed = Defaults.Key.keysRemoved(
            applying: ["A": 1],
            over: ["C": 2, "A": 0, "B": 1],
            removesMissingKeys: true
        )
        #expect(removed == ["B", "C"])
    }

    @Test("A setting in both is never removed")
    func keyInBothIsKept() {
        let current: [String: Any] = ["A": 0, "B": 1]
        let accepted: [String: Any] = ["A": 1, "B": 2]
        #expect(Defaults.Key.keysRemoved(applying: accepted, over: current, removesMissingKeys: true).isEmpty)
        #expect(Defaults.Key.keysRemoved(applying: accepted, over: current, removesMissingKeys: false).isEmpty)
    }

    @Test("Settings keep their kinds")
    func settingsKeepTheirKinds() {
        #expect(Defaults.Key.hotkeys.settingsKind == .dictionary)
        #expect(Defaults.Key.showOnHover.settingsKind == .bool)
        #expect(Defaults.Key.showOnHoverDelay.settingsKind == .number)
        #expect(Defaults.Key.layoutProfiles.settingsKind == .data)
        #expect(Defaults.Key.knownItemTags.settingsKind == .stringArray)
        #expect(Defaults.Key.currentLayoutProfile.settingsKind == .string)
    }
}
