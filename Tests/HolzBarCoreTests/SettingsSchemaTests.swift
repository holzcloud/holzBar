import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSchema")
struct SettingsSchemaTests {
    /// holzBar's bundle identifier, which the app passes as `Constants.bundleIdentifier`.
    private let ownBundle = "com.holzcloud.holzBar"

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

    @Test("A settings file cannot set the key the 0.0.7 betas used for settings sync")
    func settingsFileCannotSetLeftoverKey() {
        #expect(Defaults.Key.localOnlyKeys.contains(.syncsSettingsWithICloud))
        #expect(Defaults.Key.importableKinds["SyncsSettingsWithICloud"] == nil)
        let result = Defaults.Key.validatedSettings(["SyncsSettingsWithICloud": true, "ShowOnHover": true], ownBundleIdentifier: ownBundle)
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["SyncsSettingsWithICloud"])
    }

    @Test("A settings file cannot drop event barrier exits")
    func settingsFileCannotDropBarrierExits() {
        #expect(Defaults.Key.localOnlyKeys.contains(.debugDropsBarrierExitEvent))
        #expect(Defaults.Key.importableKinds["DebugDropsBarrierExitEvent"] == nil)
        let result = Defaults.Key.validatedSettings(["DebugDropsBarrierExitEvent": true, "ShowOnHover": true], ownBundleIdentifier: ownBundle)
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["DebugDropsBarrierExitEvent"])
    }

    @Test("A settings file cannot hang item captures")
    func settingsFileCannotHangItemCaptures() {
        #expect(Defaults.Key.localOnlyKeys.contains(.debugHangsItemImageCapture))
        #expect(Defaults.Key.importableKinds["DebugHangsItemImageCapture"] == nil)
        let result = Defaults.Key.validatedSettings(["DebugHangsItemImageCapture": true, "ShowOnHover": true], ownBundleIdentifier: ownBundle)
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["DebugHangsItemImageCapture"])
    }

    @Test("Numbers out of range are clamped, and infinity and NaN refused")
    func numbersAreClamped() {
        let result = Defaults.Key.validatedSettings([
            "ItemSpacingOffset": 1e300,
            "RehideInterval": -5.0,
            "ShowOnHoverDelay": Double.nan,
            "TempShowInterval": Double.infinity,
            "SpacerWidth": 30.0,
        ], ownBundleIdentifier: ownBundle)
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
        ], ownBundleIdentifier: ownBundle)
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
        #expect(Defaults.Key.debugDropsBarrierExitEvent.rawValue == "DebugDropsBarrierExitEvent")
        #expect(Defaults.Key.debugHangsItemImageCapture.rawValue == "DebugHangsItemImageCapture")
        #expect(Defaults.Key.hotkeys.rawValue == "Hotkeys")
        #expect(Defaults.Key.menuBarAppearanceConfigurationV2.rawValue == "MenuBarAppearanceConfigurationV2")
        #expect(Defaults.Key.holzBarIconShowsCaptureDot.rawValue == "HolzBarIconShowsCaptureDot")
        #expect(Defaults.Key.widgets.rawValue == "Widgets")
        #expect(Defaults.Key.widgetShortcutNames.rawValue == "WidgetShortcutNames")
    }

    @Test("A file import removes the settings the file lacks")
    func importRemovesMissingKeys() {
        let removed = Defaults.Key.keysRemoved(
            applying: ["A": 1],
            over: ["C": 2, "A": 0, "B": 1]
        )
        #expect(removed == ["B", "C"])
    }

    @Test("A setting in both is never removed")
    func keyInBothIsKept() {
        let current: [String: Any] = ["A": 0, "B": 1]
        let accepted: [String: Any] = ["A": 1, "B": 2]
        #expect(Defaults.Key.keysRemoved(applying: accepted, over: current).isEmpty)
    }

    @Test("Settings keep their kinds")
    func settingsKeepTheirKinds() {
        #expect(Defaults.Key.hotkeys.settingsKind == .dictionary)
        #expect(Defaults.Key.showOnHover.settingsKind == .bool)
        #expect(Defaults.Key.holzBarIconShowsCaptureDot.settingsKind == .bool)
        #expect(Defaults.Key.showOnHoverDelay.settingsKind == .number)
        #expect(Defaults.Key.layoutProfiles.settingsKind == .data)
        #expect(Defaults.Key.automationRules.settingsKind == .data)
        #expect(Defaults.Key.knownItemTags.settingsKind == .stringArray)
        #expect(Defaults.Key.currentLayoutProfile.settingsKind == .string)
    }

    @Test("The lock for hidden items and the assistant flag are local to the Mac")
    func localKeys() {
        #expect(Defaults.Key.localOnlyKeys.contains(.lockHiddenItems))
        #expect(Defaults.Key.localOnlyKeys.contains(.cleanUpOffered))
        let result = Defaults.Key.validatedSettings(["LockHiddenItems": false, "ShowOnHover": true], ownBundleIdentifier: ownBundle)
        #expect(result.ignored == ["LockHiddenItems"])
        #expect(result.accepted["ShowOnHover"] as? Bool == true)
    }

    @Test("An imported rule list loses the rules that use a script")
    func importedRulesLoseScripts() throws {
        let plain = AutomationRule(
            name: "Plain",
            clauses: [AutomationClause(condition: .lowPowerMode)],
            action: .zen(true)
        )
        let scripted = AutomationRule(
            name: "Scripted",
            clauses: [AutomationClause(condition: .lowPowerMode)],
            action: .runScript("go.sh")
        )
        let data = try JSONEncoder().encode([plain, scripted])
        let result = Defaults.Key.validatedSettings(["AutomationRules": data], ownBundleIdentifier: ownBundle)
        let accepted = try #require(result.accepted["AutomationRules"] as? Data)
        let rules = try JSONDecoder().decode([AutomationRule].self, from: accepted)
        #expect(rules == [plain])
        let broken = Defaults.Key.validatedSettings(["AutomationRules": Data("nonsense".utf8)], ownBundleIdentifier: ownBundle)
        #expect(broken.accepted["AutomationRules"] == nil)
        #expect(broken.ignored == ["AutomationRules"])
    }

    @Test("The widgets travel, their Shortcut names stay (D-25)")
    func widgetsTravelShortcutNamesStay() {
        #expect(Defaults.Key.widgets.settingsKind == .data)
        #expect(Defaults.Key.widgetShortcutNames.settingsKind == .dictionary)
        #expect(!Defaults.Key.localOnlyKeys.contains(.widgets))
        #expect(Defaults.Key.localOnlyKeys.contains(.widgetShortcutNames))
        #expect(Defaults.Key.importableKinds["Widgets"] == .data)
        #expect(Defaults.Key.importableKinds["WidgetShortcutNames"] == nil)
        let result = Defaults.Key.validatedSettings([
            "WidgetShortcutNames": ["0A1B2C3D-0000-4000-8000-000000000001": "Focus"],
            "ShowOnHover": true,
        ], ownBundleIdentifier: ownBundle)
        #expect(result.ignored == ["WidgetShortcutNames"])
        #expect(result.accepted["ShowOnHover"] as? Bool == true)
    }

    @Test("An imported widget list is normalised before it is applied (D-25, T-12-04)")
    func importedWidgetsAreNormalised() throws {
        let elements: [[String: Any]] = (0..<7).map { index in
            [
                "id": UUID().uuidString,
                "kind": "text",
                "source": "cpu",
                "preset": "percent",
                "refreshSeconds": 5,
                "shortcutName": "Secret \(index)",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: elements)
        let result = Defaults.Key.validatedSettings(["Widgets": data], ownBundleIdentifier: ownBundle)
        let accepted = try #require(result.accepted["Widgets"] as? Data)
        #expect(result.ignored.isEmpty)
        let objects = try #require(try JSONSerialization.jsonObject(with: accepted) as? [[String: Any]])
        #expect(objects.count == 6)
        #expect(objects.allSatisfy { $0["shortcutName"] == nil })
        #expect(WidgetList.decode(accepted).count == 6)
        let broken = Defaults.Key.validatedSettings(["Widgets": Data(#"{"kind": "text"}"#.utf8)], ownBundleIdentifier: ownBundle)
        #expect(broken.accepted["Widgets"] == nil)
        #expect(broken.ignored == ["Widgets"])
    }

    @Test("A settings file never conceals holzBar itself in the macOS 27 layout (WR-01)")
    func settingsFileCannotConcealHolzBar() throws {
        let widget = "holzBar.Widget.0A1B2C3D-0000-4000-8000-000000000001"
        let result = Defaults.Key.validatedSettings(
            ["MacOS27Layout": ["com.holzcloud.holzBar": 2, "com.holzcloud.holzbar": 1, "com.example.tool": 1, widget: 1]],
            ownBundleIdentifier: ownBundle
        )
        let layout = try #require(result.accepted["MacOS27Layout"] as? [String: Int])
        #expect(layout == ["com.example.tool": 1, widget: 1])
        #expect(result.ignored.isEmpty)

        // The identifier is the caller's: another build's own bundle is the one refused.
        let fork = Defaults.Key.validatedSettings(
            ["MacOS27Layout": ["com.example.fork": 2, "com.holzcloud.holzBar": 1]],
            ownBundleIdentifier: "com.example.fork"
        )
        #expect(fork.accepted["MacOS27Layout"] as? [String: Int] == ["com.holzcloud.holzBar": 1])
    }
}
