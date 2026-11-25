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

    @Test("The Read badge counts switch is a local-only Boolean that no file can set")
    func dockBadgesReadsCountsStaysLocal() {
        #expect(Defaults.Key.dockBadgesReadsCounts.rawValue == "DockBadgesReadsCounts")
        #expect(Defaults.Key.dockBadgesReadsCounts.settingsKind == .bool)
        #expect(Defaults.Key.localOnlyKeys.contains(.dockBadgesReadsCounts))
        #expect(Defaults.Key.importableKinds["DockBadgesReadsCounts"] == nil)
        let result = Defaults.Key.validatedSettings(
            ["DockBadgesReadsCounts": true, "ShowOnHover": true],
            ownBundleIdentifier: ownBundle
        )
        #expect(result.accepted.keys.sorted() == ["ShowOnHover"])
        #expect(result.ignored == ["DockBadgesReadsCounts"])
    }

    // MARK: Zero mode

    @Test("The zero mode has two choices with fixed raw values; nothing stored, or an unknown value, is Dim")
    func zeroModeRawValues() {
        #expect(DockBadgeZeroMode(rawValue: 0) == .dim)
        #expect(DockBadgeZeroMode(rawValue: 1) == .hide)
        #expect(DockBadgeZeroMode(rawValue: 2) == nil)
        #expect(DockBadgeZeroMode.allCases == [.dim, .hide])
        #expect(DockBadgeZeroMode.stored(nil) == .dim)
        #expect(DockBadgeZeroMode.stored(0) == .dim)
        #expect(DockBadgeZeroMode.stored(1) == .hide)
        #expect(DockBadgeZeroMode.stored(2) == .dim)
        #expect(DockBadgeZeroMode.stored(-1) == .dim)
    }

    @Test("The zero mode travels with a settings file, as 0 or 1 only")
    func dockBadgeZeroModeTravels() {
        #expect(Defaults.Key.dockBadgeZeroMode.rawValue == "DockBadgeZeroMode")
        #expect(Defaults.Key.dockBadgeZeroMode.settingsKind == .number)
        #expect(Defaults.Key.dockBadgeZeroMode.numberRule == .wholeNumber(0...1))
        #expect(!Defaults.Key.localOnlyKeys.contains(.dockBadgeZeroMode))
        #expect(Defaults.Key.importableKinds["DockBadgeZeroMode"] == .number)
        for accepted: Any in [0, 1] {
            let result = Defaults.Key.validatedSettings(["DockBadgeZeroMode": accepted], ownBundleIdentifier: ownBundle)
            #expect((result.accepted["DockBadgeZeroMode"] as? NSNumber)?.intValue == (accepted as? Int))
        }
        for refused: Any in [2, 0.5, -1] {
            let result = Defaults.Key.validatedSettings(["DockBadgeZeroMode": refused], ownBundleIdentifier: ownBundle)
            #expect(result.accepted["DockBadgeZeroMode"] == nil)
            #expect(result.ignored == ["DockBadgeZeroMode"])
        }
    }

    // MARK: Item names

    @Test("An app's item name carries its bundle identifier and round-trips")
    func itemNameRoundTrips() {
        let name = DockBadgeItemName.app("com.apple.MobileSMS")
        #expect(name == "holzBar.DockBadge.App.com.apple.MobileSMS")
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: name) == "com.apple.MobileSMS")
        #expect(DockBadgeItemName.isAutosaveName(name))
    }

    @Test("Other names, and an empty or invalid bundle identifier, give no app")
    func itemNameRefusesOthers() {
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "holzBar.Widget.0F3A") == nil)
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "holzBar.Replacement.com.apple.controlcenter") == nil)
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "holzBar.StandIn.com.apple.Safari") == nil)
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "holzBar.DockBadge.App.") == nil)
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "holzBar.DockBadge.App.not a bundle id") == nil)
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: "") == nil)
        #expect(!DockBadgeItemName.isAutosaveName("holzBar.Widget.0F3A"))
        #expect(!DockBadgeItemName.isAutosaveName("com.apple.Safari"))
        // A name is an item's only when it names a valid app, never by its prefix alone.
        #expect(!DockBadgeItemName.isAutosaveName("holzBar.DockBadge.App."))
        #expect(!DockBadgeItemName.isAutosaveName("holzBar.DockBadge."))
    }

    // MARK: Groups

    private let chat = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let work = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func group(_ id: UUID, _ name: String, _ apps: [String]) -> DockBadgeGroup {
        DockBadgeGroup(id: id, name: name, apps: apps)
    }

    private func data(_ groups: [DockBadgeGroup]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(groups)) ?? Data()
    }

    @Test("A valid list is kept as it is, and encodes and decodes to the same groups")
    func groupListKeepsAValidList() {
        let groups = [group(chat, "Chat", ["com.apple.MobileSMS", "com.tinyspeck.slackmacgap"]), group(work, "Work", ["com.apple.mail"])]
        let encoded = DockBadgeGroupList.encode(groups)
        #expect(encoded != nil)
        #expect(DockBadgeGroupList.decode(encoded ?? Data()) == groups)
        #expect(DockBadgeGroupList.normalized(data(groups)) == encoded)
    }

    @Test("Names are trimmed, line breaks and runs of white space become one space, and a long name is cut to 64")
    func groupListCleansNames() {
        let long = String(repeating: "x", count: 100)
        let groups = [group(chat, "  Chat \n room ", []), group(work, long, [])]
        let result = DockBadgeGroupList.decode(data(groups))
        #expect(result.map(\.name) == ["Chat room", String(repeating: "x", count: 64)])
        #expect(DockBadgeGroupList.cleanedName("   ") == nil)
        #expect(DockBadgeGroupList.cleanedName("") == nil)
    }

    @Test("A group with an empty name or a repeated identifier is dropped")
    func groupListDropsBadGroups() {
        let groups = [
            group(chat, "Chat", []), group(UUID(), "   ", []), group(chat, "Again", []), group(work, "Work", []),
        ]
        #expect(DockBadgeGroupList.decode(data(groups)).map(\.name) == ["Chat", "Work"])
    }

    @Test("An app stays only in its first group, and bundle identifiers are sanitized")
    func groupListKeepsAnAppOnce() {
        let groups = [
            group(chat, "Chat", ["com.apple.MobileSMS", "not a bundle id", "com.apple.MobileSMS", ""]),
            group(work, "Work", ["com.apple.MobileSMS", "com.apple.mail"]),
        ]
        let result = DockBadgeGroupList.decode(data(groups))
        #expect(result.map(\.apps) == [["com.apple.MobileSMS"], ["com.apple.mail"]])
    }

    @Test("At most 12 groups are kept")
    func groupListCapsTheCount() {
        let groups = (0..<20).map { group(UUID(), "Group \($0)", []) }
        let result = DockBadgeGroupList.decode(data(groups))
        #expect(result.count == 12)
        #expect(result.map(\.name) == (0..<12).map { "Group \($0)" })
    }

    @Test("Data that is not the JSON list, or is too large, is refused; an element that does not decode is skipped")
    func groupListRefusesBadData() {
        #expect(DockBadgeGroupList.normalized(Data("not json".utf8)) == nil)
        #expect(DockBadgeGroupList.normalized(Data("{\"a\": 1}".utf8)) == nil)
        #expect(DockBadgeGroupList.normalized(Data(count: 70_000)) == nil)
        #expect(DockBadgeGroupList.decode(Data("not json".utf8)).isEmpty)
        let mixed = Data("[1, {\"id\": \"\(chat.uuidString)\", \"name\": \"Chat\", \"apps\": []}, {\"id\": \"x\"}]".utf8)
        #expect(DockBadgeGroupList.decode(mixed).map(\.name) == ["Chat"])
        #expect(DockBadgeGroupList.normalized(Data("[]".utf8)) == Data("[]".utf8))
    }

    @Test("Assigning moves an app from one group to another, and nil takes it out of every group")
    func groupListAssigns() {
        let groups = [group(chat, "Chat", ["com.apple.MobileSMS", "com.apple.mail"]), group(work, "Work", [])]
        let moved = DockBadgeGroupList.assigning("com.apple.MobileSMS", to: work, in: groups)
        #expect(moved.map(\.apps) == [["com.apple.mail"], ["com.apple.MobileSMS"]])
        let again = DockBadgeGroupList.assigning("com.apple.MobileSMS", to: work, in: moved)
        #expect(again == moved)
        let removed = DockBadgeGroupList.assigning("com.apple.mail", to: nil, in: moved)
        #expect(removed.map(\.apps) == [[], ["com.apple.MobileSMS"]])
        // An unknown group or an invalid identifier changes nothing.
        #expect(DockBadgeGroupList.assigning("com.apple.mail", to: UUID(), in: groups) == groups)
        #expect(DockBadgeGroupList.assigning("not a bundle id", to: work, in: groups) == groups)
    }

    @Test("Removing an app takes it out of every group")
    func groupListRemovesAnApp() {
        let groups = [group(chat, "Chat", ["com.apple.MobileSMS"]), group(work, "Work", ["com.apple.mail"])]
        #expect(DockBadgeGroupList.removingApp("com.apple.mail", from: groups).map(\.apps) == [["com.apple.MobileSMS"], []])
        #expect(DockBadgeGroupList.removingApp("com.example.none", from: groups) == groups)
    }

    @Test("A deleted group comes back at its place without apps another group took meanwhile, and not twice")
    func groupListReinserts() {
        let deleted = group(chat, "Chat", ["com.apple.MobileSMS", "com.apple.mail"])
        let now = [group(work, "Work", ["com.apple.mail"])]
        let back = DockBadgeGroupList.reinserting(deleted, at: 0, into: now)
        #expect(back.map(\.name) == ["Chat", "Work"])
        #expect(back.map(\.apps) == [["com.apple.MobileSMS"], ["com.apple.mail"]])
        #expect(DockBadgeGroupList.reinserting(deleted, at: 0, into: back) == back)
        #expect(DockBadgeGroupList.reinserting(deleted, at: 9, into: now).map(\.name) == ["Work", "Chat"])
        let full = (0..<12).map { group(UUID(), "G\($0)", []) }
        #expect(DockBadgeGroupList.reinserting(deleted, at: 0, into: full) == full)
    }

    @Test("The items are the chosen apps outside every group in chosen order, then each group with a chosen member")
    func itemListOrder() {
        let apps = ["com.a.one", "com.a.two", "com.a.three", "com.a.four"]
        let groups = [
            group(chat, "Chat", ["com.a.two", "com.a.four", "com.a.gone"]),
            group(work, "Work", ["com.a.gone"]),
        ]
        let items = DockBadgeItemList.items(apps: apps, groups: groups)
        #expect(items == [.app("com.a.one"), .app("com.a.three"), .group(chat)])
        #expect(DockBadgeItemList.members(of: groups[0], in: groups, apps: apps) == ["com.a.two", "com.a.four"])
        #expect(DockBadgeItemList.members(of: groups[1], in: groups, apps: apps).isEmpty)
    }

    @Test("An app is never twice and a group without a chosen member has no item, even in a list that was not normalized")
    func itemListNeverTwice() {
        let apps = ["com.a.one", "com.a.two", "com.a.one"]
        let groups = [group(chat, "Chat", ["com.a.one"]), group(work, "Work", ["com.a.one", "com.a.two"])]
        let items = DockBadgeItemList.items(apps: apps, groups: groups)
        #expect(items == [.group(chat), .group(work)])
        #expect(DockBadgeItemList.members(of: groups[1], in: groups, apps: apps) == ["com.a.two"])
        #expect(DockBadgeItemList.items(apps: apps, groups: []) == [.app("com.a.one"), .app("com.a.two")])
        #expect(DockBadgeItemList.items(apps: [], groups: groups).isEmpty)
    }

    @Test("The item kinds name their items")
    func itemKindNames() {
        #expect(DockBadgeItemKind.app("com.apple.Safari").autosaveName == DockBadgeItemName.app("com.apple.Safari"))
        #expect(DockBadgeItemKind.group(chat).autosaveName == "holzBar.DockBadge.Group.11111111-1111-1111-1111-111111111111")
    }

    @Test("A group's item name carries its identifier, round-trips and is recognised")
    func groupItemNameRoundTrips() {
        let name = DockBadgeItemName.group(chat)
        #expect(name == "holzBar.DockBadge.Group.11111111-1111-1111-1111-111111111111")
        #expect(DockBadgeItemName.groupID(fromAutosaveName: name) == chat)
        #expect(DockBadgeItemName.isAutosaveName(name))
        #expect(DockBadgeItemName.bundleID(fromAutosaveName: name) == nil)
        #expect(DockBadgeItemName.groupID(fromAutosaveName: DockBadgeItemName.app("com.apple.Safari")) == nil)
    }

    @Test("A name is a group's only when it holds a canonical identifier")
    func groupItemNameRefusesOthers() {
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "holzBar.DockBadge.Group.") == nil)
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "holzBar.DockBadge.Group.not-a-uuid") == nil)
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "holzBar.DockBadge.Group.11111111-1111-1111-1111-111111111111x") == nil)
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "holzBar.Group.11111111-1111-1111-1111-111111111111") == nil)
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "") == nil)
        #expect(!DockBadgeItemName.isAutosaveName("holzBar.DockBadge.Group."))
        #expect(!DockBadgeItemName.isAutosaveName("holzBar.DockBadge.Group.not-a-uuid"))
        // The lower-case form is another name for the same identifier and is refused, so one group
        // has one autosave name.
        #expect(DockBadgeItemName.groupID(fromAutosaveName: "holzBar.DockBadge.Group.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") == nil)
    }

    @Test("The groups are a data key that travels with an exported settings file and is normalized on import")
    func dockBadgeGroupsIsNormalized() {
        #expect(Defaults.Key.dockBadgeGroups.rawValue == "DockBadgeGroups")
        #expect(Defaults.Key.dockBadgeGroups.settingsKind == .data)
        #expect(!Defaults.Key.localOnlyKeys.contains(.dockBadgeGroups))
        #expect(Defaults.Key.importableKinds["DockBadgeGroups"] == .data)
        let tampered = [
            group(chat, "  Chat  ", ["com.apple.MobileSMS", "not a bundle id"]),
            group(work, "Work", ["com.apple.MobileSMS", "com.apple.mail"]),
            group(UUID(), "", []),
        ]
        let result = Defaults.Key.validatedSettings(["DockBadgeGroups": data(tampered)], ownBundleIdentifier: ownBundle)
        let accepted = result.accepted["DockBadgeGroups"] as? Data
        #expect(accepted != nil)
        let decoded = DockBadgeGroupList.decode(accepted ?? Data())
        #expect(decoded.map(\.name) == ["Chat", "Work"])
        #expect(decoded.map(\.apps) == [["com.apple.MobileSMS"], ["com.apple.mail"]])
        #expect(result.ignored.isEmpty)
    }

    @Test("Malformed group data is ignored, and a value of the wrong kind is ignored")
    func dockBadgeGroupsRefusesMalformed() {
        let malformed = Defaults.Key.validatedSettings(["DockBadgeGroups": Data("not json".utf8)], ownBundleIdentifier: ownBundle)
        #expect(malformed.accepted["DockBadgeGroups"] == nil)
        #expect(malformed.ignored == ["DockBadgeGroups"])
        let wrongKind = Defaults.Key.validatedSettings(["DockBadgeGroups": "Chat"], ownBundleIdentifier: ownBundle)
        #expect(wrongKind.accepted["DockBadgeGroups"] == nil)
        #expect(wrongKind.ignored == ["DockBadgeGroups"])
    }
}
