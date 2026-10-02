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

    @Test("Every stored key is importable")
    func everyStoredKeyIsImportable() {
        let rawValues = Defaults.Key.allCases.map(\.rawValue)
        #expect(Defaults.Key.importableKinds.count == rawValues.count)
        #expect(Set(Defaults.Key.importableKinds.keys) == Set(rawValues))
        for key in Defaults.Key.allCases {
            #expect(Defaults.Key.importableKinds[key.rawValue] == key.settingsKind)
        }
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
