import Foundation
import Testing
@testable import HolzBarCore

@Suite("AppleItemReplacement")
struct AppleItemReplacementTests {
    private func data(_ elements: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: elements)
    }

    private func element(
        _ id: UUID = UUID(),
        key: String = "com.apple.controlcenter:FocusModes",
        title: String = "Focus",
        symbol: String = "moon",
        _ extra: [String: Any] = [:]
    ) -> [String: Any] {
        var result: [String: Any] = ["id": id.uuidString, "itemKey": key, "title": title, "symbolName": symbol]
        result.merge(extra) { _, new in new }
        return result
    }

    // MARK: The catalog

    @Test("Items of Apple applications can be replaced")
    func replaceableKeys() {
        for key in [
            "com.apple.controlcenter:FocusModes",
            "com.apple.systemuiserver:com.apple.menuextra.TimeMachine",
            "com.apple.controlcenter:2",
            "com.apple.controlcenter",
        ] {
            #expect(AppleItemCatalog.isReplaceable(itemKey: key), "\(key)")
        }
    }

    @Test("Other items, the numbered system items and malformed keys cannot")
    func notReplaceableKeys() {
        for key in [
            "com.apple.MenuBarAgent:com.apple.menuextra.clock",
            "com.apple.menubaragent:x",
            "com.apple.MenuBarAgent",
            "com.example.app:Item-0",
            "com.holzcloud.holzBar:x",
            "COM.APPLE.x:y",
            "com.apple.:y",
            "com.apple.",
            "",
            String(repeating: "a", count: 256),
            "com.apple.controlcenter:Focus\nModes",
            "com.apple.controlcenter:Focus\u{0}Modes",
            "com.apple.controlcenter:Focus\u{202E}Modes",
        ] {
            #expect(!AppleItemCatalog.isReplaceable(itemKey: key), "\(key.prefix(40))")
        }
    }

    @Test("A key of 255 bytes is the longest that can be replaced")
    func keyLengthLimit() {
        let prefix = "com.apple.x:"
        let longest = prefix + String(repeating: "a", count: 255 - prefix.utf8.count)
        #expect(AppleItemCatalog.isReplaceable(itemKey: longest))
        #expect(!AppleItemCatalog.isReplaceable(itemKey: longest + "a"))
    }

    @Test("The suggested symbols fit the item and are all offered")
    func suggestedSymbols() {
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.controlcenter:FocusModes") == "moon")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.NowPlaying") == "music.note")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.systemuiserver:com.apple.menuextra.TimeMachine") == "clock.arrow.circlepath")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.UserSwitcher") == "person.crop.circle")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.AirDrop") == "antenna.radiowaves.left.and.right")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.TextInput") == "keyboard")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.Keyboard") == "keyboard")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.menuextra.display") == "display")
        #expect(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.other:Thing") == AppleItemCatalog.defaultSymbolName)
        for key in ["focus", "nowplaying", "timemachine", "userswitcher", "airdrop", "textinput", "keyboard", "display", "other"] {
            #expect(AppleItemCatalog.symbolNames.contains(AppleItemCatalog.suggestedSymbol(forItemKey: "com.apple.\(key)")))
        }
        #expect(AppleItemCatalog.symbolNames.contains(AppleItemCatalog.defaultSymbolName))
        #expect(Set(AppleItemCatalog.symbolNames).count == AppleItemCatalog.symbolNames.count)
    }

    // MARK: The list

    @Test("A valid list round-trips unchanged")
    func roundTrip() throws {
        let list = [
            AppleItemReplacement(id: UUID(), itemKey: "com.apple.controlcenter:FocusModes", title: "Focus", symbolName: "moon"),
            AppleItemReplacement(id: UUID(), itemKey: "com.apple.menuextra.AirDrop", title: "AirDrop", symbolName: "antenna.radiowaves.left.and.right"),
        ]
        let encoded = try #require(AppleItemReplacementList.encoded(list))
        #expect(AppleItemReplacementList.decode(encoded) == list)
        #expect(AppleItemReplacementList.normalized(encoded) == encoded)
    }

    @Test("At most six replacements are kept")
    func sixAtMost() throws {
        let elements = (0..<9).map { element(key: "com.apple.app\($0):Item", title: "Item \($0)") }
        let list = AppleItemReplacementList.decode(try data(elements))
        #expect(list.count == 6)
        #expect(list.map(\.title) == (0..<6).map { "Item \($0)" })
    }

    @Test("A second element with the same identifier or the same key is dropped")
    func duplicates() throws {
        let id = UUID()
        let json = try data([
            element(id, key: "com.apple.a:One", title: "One"),
            element(id, key: "com.apple.b:Two", title: "Two"),
            element(key: "com.apple.a:One", title: "Again"),
            element(key: "com.apple.c:Three", title: "Three"),
        ])
        #expect(AppleItemReplacementList.decode(json).map(\.title) == ["One", "Three"])
    }

    @Test("An item of another vendor or a numbered system item is dropped")
    func foreignItems() throws {
        let json = try data([
            element(key: "com.example.app:Item-0", title: "Foreign"),
            element(key: "com.apple.MenuBarAgent:com.apple.menuextra.clock", title: "Clock"),
            element(key: "com.apple.controlcenter:FocusModes", title: "Focus"),
        ])
        #expect(AppleItemReplacementList.decode(json).map(\.title) == ["Focus"])
    }

    @Test("An unknown symbol becomes the default and a missing one too")
    func unknownSymbol() throws {
        var missing = element(key: "com.apple.b:Two", title: "Two")
        missing["symbolName"] = nil
        let json = try data([element(key: "com.apple.a:One", title: "One", symbol: "../../evil"), missing])
        let list = AppleItemReplacementList.decode(json)
        #expect(list.map(\.symbolName) == ["star", "star"])
    }

    @Test("A name is cleaned of control characters and cut to 24 characters")
    func cleanedNames() throws {
        let json = try data([
            element(key: "com.apple.a:One", title: "Fo\u{0}cus\u{202E}\nMode"),
            element(key: "com.apple.b:Two", title: String(repeating: "x", count: 100)),
        ])
        let list = AppleItemReplacementList.decode(json)
        #expect(list[0].title == "FocusMode")
        #expect(list[1].title.count == 24)
    }

    @Test("An entry whose name is empty once cleaned is dropped")
    func emptyNames() throws {
        var missing = element(key: "com.apple.c:Three", title: "Three")
        missing["title"] = nil
        let json = try data([
            element(key: "com.apple.a:One", title: ""),
            element(key: "com.apple.b:Two", title: "\u{0}\u{202E}  \n"),
            missing,
            element(key: "com.apple.d:Four", title: "Four"),
        ])
        #expect(AppleItemReplacementList.decode(json).map(\.title) == ["Four"])
    }

    @Test("Data over the size limit or not a list is refused")
    func sizeAndShape() {
        #expect(AppleItemReplacementList.maximumDataSize == 16_384)
        let big = Data(repeating: 0x20, count: AppleItemReplacementList.maximumDataSize + 1)
        #expect(AppleItemReplacementList.decode(big).isEmpty)
        #expect(AppleItemReplacementList.normalized(big) == nil)
        let object = Data(#"{"id": "x"}"#.utf8)
        #expect(AppleItemReplacementList.decode(object).isEmpty)
        #expect(AppleItemReplacementList.normalized(object) == nil)
        #expect(AppleItemReplacementList.normalized(Data("nonsense".utf8)) == nil)
        #expect(AppleItemReplacementList.normalized(Data("[]".utf8)) == Data("[]".utf8))
    }

    @Test("One broken element drops only itself")
    func brokenElement() throws {
        let json = Data(#"""
        [
          {"id": "not a uuid", "itemKey": "com.apple.a:One", "title": "One", "symbolName": "moon"},
          42,
          {"id": "\#(UUID().uuidString)", "itemKey": 7, "title": "Seven", "symbolName": "moon"},
          {"id": "\#(UUID().uuidString)", "itemKey": "com.apple.d:Four", "title": "Four", "symbolName": "bell"}
        ]
        """#.utf8)
        #expect(AppleItemReplacementList.decode(json).map(\.title) == ["Four"])
    }

    @Test("A normalized list has no unknown fields")
    func normalization() throws {
        let elements = (0..<7).map { element(key: "com.apple.a\($0):Item", title: "Item \($0)", ["extra": "x\($0)"]) }
        let normalized = try #require(AppleItemReplacementList.normalized(try data(elements)))
        let objects = try #require(try JSONSerialization.jsonObject(with: normalized) as? [[String: Any]])
        #expect(objects.count == 6)
        #expect(objects.allSatisfy { $0["extra"] == nil })
        #expect(Set(objects.flatMap(\.keys)) == ["id", "itemKey", "title", "symbolName"])
    }

    @Test("Encoding uses sorted keys and refuses a list over the size limit")
    func encoding() throws {
        let one = AppleItemReplacement(id: UUID(), itemKey: "com.apple.a:One", title: "One", symbolName: "moon")
        let encoded = try #require(AppleItemReplacementList.encoded([one]))
        let text = String(decoding: encoded, as: UTF8.self)
        let positions = ["\"id\"", "\"itemKey\"", "\"symbolName\"", "\"title\""].compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == 4)
        #expect(positions == positions.sorted())
        let huge = Array(repeating: AppleItemReplacement(id: UUID(), itemKey: "com.apple.a:" + String(repeating: "k", count: 200), title: "Huge", symbolName: "moon"), count: 100)
        #expect(AppleItemReplacementList.encoded(huge) == nil)
    }

    @Test("The autosave name is the prefix and the uppercase identifier, and reads back")
    func autosaveNames() throws {
        let id = UUID()
        let replacement = AppleItemReplacement(id: id, itemKey: "com.apple.a:One", title: "One", symbolName: "moon")
        #expect(AppleItemReplacement.autosaveNamePrefix == "holzBar.Replacement.")
        #expect(replacement.autosaveName == "holzBar.Replacement." + id.uuidString)
        #expect(AppleItemReplacement.id(fromAutosaveName: replacement.autosaveName) == id)
        #expect(AppleItemReplacement.id(fromAutosaveName: "holzBar.Replacement." + id.uuidString.lowercased()) == nil)
        #expect(AppleItemReplacement.id(fromAutosaveName: "holzBar.Group." + id.uuidString) == nil)
        #expect(AppleItemReplacement.id(fromAutosaveName: "holzBar.Widget." + id.uuidString) == nil)
        #expect(AppleItemReplacement.id(fromAutosaveName: "holzBar.Replacement.") == nil)
        #expect(AppleItemReplacement.id(fromAutosaveName: "") == nil)
        #expect(!WidgetDefinition.isAutosaveName(replacement.autosaveName))
    }

    // MARK: The import path

    private let ownBundle = "com.holzcloud.holzBar"

    @Test("A settings file brings only the valid, corrected and cleaned replacements")
    func importNormalizes() throws {
        let duplicateID = UUID()
        let elements = [
            element(key: "com.apple.controlcenter:FocusModes", title: "Focus"),
            element(key: "com.example.app:Item-0", title: "Foreign"),
            element(key: "com.apple.MenuBarAgent:com.apple.menuextra.clock", title: "Clock"),
            element(key: "com.apple.a:Symbol", title: "Symbol", symbol: "bogus.symbol"),
            element(key: "com.apple.b:Control", title: "Con\u{0}trol\u{202E}"),
            element(key: "com.apple.controlcenter:FocusModes", title: "Same key"),
            element(duplicateID, key: "com.apple.c:One", title: "One"),
            element(duplicateID, key: "com.apple.d:Two", title: "Two"),
        ]
        let result = Defaults.Key.validatedSettings(["AppleItemReplacements": try data(elements)], ownBundleIdentifier: ownBundle)
        #expect(result.ignored.isEmpty)
        let accepted = try #require(result.accepted["AppleItemReplacements"] as? Data)
        let list = AppleItemReplacementList.decode(accepted)
        #expect(list.map(\.title) == ["Focus", "Symbol", "Control", "One"])
        #expect(list.map(\.symbolName) == ["moon", "star", "moon", "moon"])
    }

    @Test("Data that is not a list is removed and reported")
    func importRefusesNonLists() {
        let result = Defaults.Key.validatedSettings(
            ["AppleItemReplacements": Data(#"{"itemKey": "com.apple.a:One"}"#.utf8)],
            ownBundleIdentifier: ownBundle
        )
        #expect(result.accepted["AppleItemReplacements"] == nil)
        #expect(result.ignored == ["AppleItemReplacements"])
    }

    @Test("Data over the size limit is removed and reported")
    func importRefusesOversize() {
        let big = Data(repeating: 0x20, count: AppleItemReplacementList.maximumDataSize + 1)
        let result = Defaults.Key.validatedSettings(["AppleItemReplacements": big], ownBundleIdentifier: ownBundle)
        #expect(result.accepted["AppleItemReplacements"] == nil)
        #expect(result.ignored == ["AppleItemReplacements"])
    }

    @Test("A value that is not data is refused by the schema")
    func importRefusesOtherKinds() {
        let result = Defaults.Key.validatedSettings(["AppleItemReplacements": "com.apple.a:One"], ownBundleIdentifier: ownBundle)
        #expect(result.accepted["AppleItemReplacements"] == nil)
        #expect(result.ignored == ["AppleItemReplacements"])
    }

    @Test("Normalizing already normalized data returns the same bytes")
    func importIsIdempotent() throws {
        let json = try data([element(key: "com.apple.a:One", title: "One"), element(key: "com.apple.b:Two", title: "Two")])
        let first = try #require(AppleItemReplacementList.normalized(json))
        #expect(AppleItemReplacementList.normalized(first) == first)
    }
}
