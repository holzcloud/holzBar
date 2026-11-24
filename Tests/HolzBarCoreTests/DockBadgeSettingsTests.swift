import Foundation
import Testing
@testable import HolzBarCore

@Suite("DockBadgeSettings")
struct DockBadgeSettingsTests {
    private let ownBundle = "com.holzcloud.holzBar"

    private func app(_ id: String, name: String = "App", running: Bool = false) -> DockAppItem {
        DockAppItem(bundleID: id, name: name, isRunning: running)
    }

    // MARK: Sanitizer

    @Test("The sanitizer drops empty strings, invalid identifiers and repeats, and keeps the first of a repeat")
    func sanitizedDropsInvalidAndRepeated() {
        let stored = [
            "com.apple.MobileSMS", "", "not a bundle id", "com.apple.Safari", "com.apple.MobileSMS", "nodots", "com.apple.Safari",
        ]
        #expect(DockBadgeApps.sanitized(stored) == ["com.apple.MobileSMS", "com.apple.Safari"])
        #expect(DockBadgeApps.sanitized([]).isEmpty)
    }

    @Test("The sanitizer keeps the order of the choice")
    func sanitizedKeepsOrder() {
        let stored = ["com.example.zed", "com.example.alpha", "com.example.mid"]
        #expect(DockBadgeApps.sanitized(stored) == stored)
    }

    @Test("The sanitizer keeps at most 64 identifiers")
    func sanitizedCapsTheCount() {
        #expect(DockBadgeApps.maximumCount == 64)
        let many = (0..<100).map { "com.example.app\($0)" }
        let kept = DockBadgeApps.sanitized(many)
        #expect(kept.count == 64)
        #expect(kept == Array(many.prefix(64)))
    }

    @Test("The sanitizer refuses an identifier over 255 bytes and one with a control character")
    func sanitizedRefusesOverlongAndControl() {
        let overlong = "com.example." + String(repeating: "a", count: 300)
        #expect(DockBadgeApps.sanitized([overlong, "com.example.ok", "com.example.bad\nline"]) == ["com.example.ok"])
    }

    // MARK: Rows

    @Test("The rows are the Dock's apps in the Dock's order with their choice")
    func rowsFollowTheDock() {
        let dock = [app("com.apple.Safari", name: "Safari"), app("com.apple.MobileSMS", name: "Messages"), app("com.apple.mail", name: "Mail")]
        let rows = DockBadgeApps.rows(chosen: ["com.apple.mail"], dock: dock)
        #expect(rows.map(\.bundleID) == ["com.apple.Safari", "com.apple.MobileSMS", "com.apple.mail"])
        #expect(rows.map(\.name) == ["Safari", "Messages", "Mail"])
        #expect(rows.map(\.isChosen) == [false, false, true])
        #expect(rows.allSatisfy { $0.isInDock })
    }

    @Test("A chosen app that is not in the Dock follows the Dock's apps, in the order chosen, marked as not in the Dock")
    func rowsKeepChosenAppsThatLeftTheDock() {
        let dock = [app("com.apple.Safari", name: "Safari")]
        let rows = DockBadgeApps.rows(chosen: ["com.example.gone", "com.apple.Safari", "com.example.also"], dock: dock)
        #expect(rows.map(\.bundleID) == ["com.apple.Safari", "com.example.gone", "com.example.also"])
        #expect(rows.map(\.isInDock) == [true, false, false])
        #expect(rows.allSatisfy { $0.isChosen })
    }

    @Test("A name for an app that is not in the Dock comes from the caller, and falls back to the identifier")
    func rowsNameAppsThatLeftTheDock() {
        let named = DockBadgeApps.rows(chosen: ["com.example.gone"], dock: []) { id in
            id == "com.example.gone" ? "Gone App" : nil
        }
        #expect(named.map(\.name) == ["Gone App"])
        let unnamed = DockBadgeApps.rows(chosen: ["com.example.gone"], dock: [])
        #expect(unnamed.map(\.name) == ["com.example.gone"])
    }

    @Test("An app twice in the Dock is one row, and the first entry gives its name")
    func rowsDeduplicate() {
        let dock = [
            app("com.apple.Safari", name: "Safari"),
            app("com.apple.mail", name: "Mail"),
            app("com.apple.Safari", name: "Safari (second)"),
        ]
        let rows = DockBadgeApps.rows(chosen: [], dock: dock)
        #expect(rows.map(\.bundleID) == ["com.apple.Safari", "com.apple.mail"])
        #expect(rows.first?.name == "Safari")
    }

    @Test("A name is cleaned: white space trimmed, line breaks made spaces, a long name cut, an empty one replaced by the identifier")
    func rowNamesAreCleaned() {
        let long = String(repeating: "x", count: 200)
        let dock = [
            app("com.example.a", name: "  Padded \n Name  "),
            app("com.example.b", name: "   "),
            app("com.example.c", name: long),
        ]
        let rows = DockBadgeApps.rows(chosen: [], dock: dock)
        #expect(rows[0].name == "Padded Name")
        #expect(rows[1].name == "com.example.b")
        #expect(rows[2].name.count == DockBadgeApps.maximumNameLength)
    }

    @Test("A row is identified by its bundle identifier")
    func rowIdentity() {
        let row = DockAppRow(bundleID: "com.apple.Safari", name: "Safari", isChosen: false, isInDock: true)
        #expect(row.id == "com.apple.Safari")
    }

    // MARK: Choosing

    @Test("Choosing an app appends it at the end; choosing it twice changes nothing")
    func settingAppends() {
        let first = DockBadgeApps.setting("com.example.b", chosen: true, in: ["com.example.a"])
        #expect(first == ["com.example.a", "com.example.b"])
        #expect(DockBadgeApps.setting("com.example.b", chosen: true, in: first) == first)
    }

    @Test("Switching an app off removes it and keeps the order of the others")
    func settingRemoves() {
        let stored = ["com.example.a", "com.example.b", "com.example.c"]
        #expect(DockBadgeApps.setting("com.example.b", chosen: false, in: stored) == ["com.example.a", "com.example.c"])
        #expect(DockBadgeApps.setting("com.example.missing", chosen: false, in: stored) == stored)
    }

    @Test("A sixty-fifth app is not added, and an invalid identifier never is")
    func settingRefusesTooManyAndInvalid() {
        let full = (0..<64).map { "com.example.app\($0)" }
        #expect(DockBadgeApps.setting("com.example.extra", chosen: true, in: full) == full)
        #expect(DockBadgeApps.setting("not valid", chosen: true, in: ["com.example.a"]) == ["com.example.a"])
        #expect(DockBadgeApps.setting("com.example.app3", chosen: false, in: full).count == 63)
    }

    // MARK: Stored key

    @Test("The chosen apps are a string list that travels with an exported settings file and is sanitized on import")
    func dockBadgeAppsIsSanitized() {
        #expect(Defaults.Key.dockBadgeApps.rawValue == "DockBadgeApps")
        #expect(Defaults.Key.dockBadgeApps.settingsKind == .stringArray)
        #expect(!Defaults.Key.localOnlyKeys.contains(.dockBadgeApps))
        let result = Defaults.Key.validatedSettings(
            ["DockBadgeApps": ["com.apple.MobileSMS", "", "com.apple.MobileSMS", "not a bundle id"], "ShowOnHover": true],
            ownBundleIdentifier: ownBundle
        )
        #expect(result.accepted["DockBadgeApps"] as? [String] == ["com.apple.MobileSMS"])
        #expect(result.ignored.isEmpty)
    }

    @Test("An imported list of more than 64 apps keeps the first 64")
    func importedListIsCapped() {
        let many = (0..<80).map { "com.example.app\($0)" }
        let result = Defaults.Key.validatedSettings(["DockBadgeApps": many], ownBundleIdentifier: ownBundle)
        #expect((result.accepted["DockBadgeApps"] as? [String])?.count == 64)
    }

    @Test("A value of the wrong kind is ignored")
    func wrongKindIsIgnored() {
        let result = Defaults.Key.validatedSettings(["DockBadgeApps": "com.apple.Safari"], ownBundleIdentifier: ownBundle)
        #expect(result.accepted["DockBadgeApps"] == nil)
        #expect(result.ignored == ["DockBadgeApps"])
    }
}
