import Foundation
import Testing
@testable import HolzBarCore

@Suite("LayoutProfileList")
struct LayoutProfileListTests {
    private func data(_ elements: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: elements)
    }

    private func element(
        _ name: String,
        items: [String: Int] = ["com.example.app:Item": 1],
        apps: [String: Int] = ["com.example.app": 2],
        _ extra: [String: Any] = [:]
    ) -> [String: Any] {
        var result: [String: Any] = ["name": name, "itemSections": items, "applicationSections": apps]
        result.merge(extra) { _, new in new }
        return result
    }

    private func profiles(_ elements: [[String: Any]]) throws -> [LayoutProfile] {
        try #require(LayoutProfileList.profiles(from: data(elements)))
    }

    // MARK: The round trip

    @Test("A valid list is kept as it is")
    func roundTrip() throws {
        let input = try data([
            element("Home", items: ["a": 0], apps: ["com.a": 1], ["knownApplications": ["com.a", "com.b"]]),
            element("Work", items: ["b": 2], apps: ["com.b": 2], ["displayUUID": "D-1", "spaceUUID": "S-1"]),
            element("Travel"),
        ])
        let list = try #require(LayoutProfileList.profiles(from: input))
        #expect(list.map(\.name) == ["Home", "Work", "Travel"])
        #expect(list[0].itemSections == ["a": 0])
        #expect(list[0].applicationSections == ["com.a": 1])
        #expect(list[0].knownApplications == ["com.a", "com.b"])
        #expect(list[1].displayUUID == "D-1")
        #expect(list[1].spaceUUID == "S-1")
        #expect(list[2].knownApplications == nil)
        #expect(list[2].displayUUID == nil)
    }

    @Test("Profiles saved by the app decode unchanged")
    func appEncodedProfilesDecode() throws {
        let saved = [
            LayoutProfile(name: "Home", itemSections: ["a": 1], applicationSections: ["com.a": 2], knownApplications: ["com.a"], displayUUID: "D", spaceUUID: nil),
            LayoutProfile(name: "Bare", itemSections: [:], applicationSections: [:]),
        ]
        let encoded = try JSONEncoder().encode(saved)
        #expect(LayoutProfileList.profiles(from: encoded) == saved)
    }

    @Test("Normalizing twice gives the same bytes")
    func idempotent() throws {
        let input = try data([
            element("Home", items: ["a": 0, "b": 1, "": 2, "c": 7], apps: ["com.a": 1], ["knownApplications": ["com.a", "com.a", ""]]),
            element(" Work\u{0007} "),
            element("Home"),
            element(String(repeating: "a", count: 79) + " b"),
        ])
        let once = try #require(LayoutProfileList.normalized(input))
        let twice = try #require(LayoutProfileList.normalized(once))
        #expect(once == twice)
    }

    // MARK: Profiles

    @Test("At most 100 profiles are kept, the first ones")
    func profileCap() throws {
        let elements = (0..<150).map { element("Profile \($0)") }
        let list = try profiles(elements)
        #expect(list.count == LayoutProfileList.maximumProfiles)
        #expect(list.first?.name == "Profile 0")
        #expect(list.last?.name == "Profile 99")
    }

    @Test("A name that is equal after cleaning is dropped")
    func duplicateNames() throws {
        let list = try profiles([element("Work", items: ["a": 0]), element(" Work "), element("Work\u{0007}", items: ["b": 0]), element("work")])
        #expect(list.map(\.name) == ["Work", "work"])
        #expect(list[0].itemSections == ["a": 0])
    }

    @Test("A name that is empty after cleaning is dropped")
    func emptyNames() throws {
        let list = try profiles([element(""), element("   "), element("\u{0007}\u{200B}"), element("Real")])
        #expect(list.map(\.name) == ["Real"])
    }

    @Test("Control characters are removed from a name and a long one is cut to 80")
    func nameCleaning() throws {
        let list = try profiles([element("Wo\u{0007}rk\n"), element(String(repeating: "x", count: 120))])
        #expect(list[0].name == "Work")
        #expect(list[1].name.count == SharedProfile.maximumNameLength)
    }

    @Test("A name cut inside a space does not end in one")
    func cutNameHasNoTrailingSpace() {
        let name = String(repeating: "a", count: 79) + " b"
        let cleaned = LayoutProfileList.cleanedName(name)
        #expect(cleaned == String(repeating: "a", count: 79))
        #expect(LayoutProfileList.cleanedName(cleaned) == cleaned)
    }

    // MARK: Entries

    @Test("At most 2000 entries per map are kept, the first by key")
    func entryCap() throws {
        let items = Dictionary(uniqueKeysWithValues: (0..<2500).map { (String(format: "item%04d", $0), 1) })
        let apps = Dictionary(uniqueKeysWithValues: (0..<2500).map { (String(format: "com.app%04d", $0), 2) })
        let list = try profiles([element("Big", items: items, apps: apps)])
        #expect(list[0].itemSections.count == LayoutProfileList.maximumEntriesPerProfile)
        #expect(list[0].applicationSections.count == LayoutProfileList.maximumEntriesPerProfile)
        #expect(list[0].itemSections["item0000"] == 1)
        #expect(list[0].itemSections["item1999"] == 1)
        #expect(list[0].itemSections["item2000"] == nil)
        #expect(list[0].applicationSections["com.app1999"] == 2)
        #expect(list[0].applicationSections["com.app2000"] == nil)
    }

    @Test("A key that is empty or over 512 bytes is dropped")
    func keyLength() throws {
        let long = String(repeating: "k", count: LayoutProfileList.maximumKeyLength + 1)
        let exact = String(repeating: "k", count: LayoutProfileList.maximumKeyLength)
        let list = try profiles([element("P", items: ["": 1, long: 1, exact: 1, "ok": 1], apps: ["": 1, long: 1, "com.ok": 1])])
        #expect(Set(list[0].itemSections.keys) == [exact, "ok"])
        #expect(Set(list[0].applicationSections.keys) == ["com.ok"])
    }

    @Test("Multi-byte keys are measured in bytes")
    func keyBytes() throws {
        // 200 characters of three bytes each are 600 bytes.
        let wide = String(repeating: "\u{20AC}", count: 200)
        let list = try profiles([element("P", items: [wide: 1, "ok": 1])])
        #expect(Set(list[0].itemSections.keys) == ["ok"])
    }

    @Test("Sections outside 0 to 2 are dropped")
    func sectionRange() throws {
        let list = try profiles([element("P", items: ["a": -1, "b": 0, "c": 2, "d": 3], apps: ["com.a": 1, "com.b": 99])])
        #expect(list[0].itemSections == ["b": 0, "c": 2])
        #expect(list[0].applicationSections == ["com.a": 1])
    }

    @Test("Known applications lose empty, long and duplicate entries and are capped")
    func knownApplications() throws {
        let long = String(repeating: "k", count: LayoutProfileList.maximumKeyLength + 1)
        let many = (0..<2500).map { String(format: "com.app%04d", $0) }
        let list = try profiles([
            element("A", ["knownApplications": ["com.a", "", long, "com.a", "com.b"]]),
            element("B", ["knownApplications": many]),
        ])
        #expect(list[0].knownApplications == ["com.a", "com.b"])
        #expect(list[1].knownApplications?.count == LayoutProfileList.maximumEntriesPerProfile)
        #expect(list[1].knownApplications?.first == "com.app0000")
    }

    @Test("A display or Space identifier that is empty or too long becomes nil")
    func identifiers() throws {
        let long = String(repeating: "u", count: LayoutProfileList.maximumIdentifierLength + 1)
        let exact = String(repeating: "u", count: LayoutProfileList.maximumIdentifierLength)
        let list = try profiles([
            element("A", ["displayUUID": "", "spaceUUID": long]),
            element("B", ["displayUUID": exact, "spaceUUID": "S"]),
        ])
        #expect(list[0].displayUUID == nil)
        #expect(list[0].spaceUUID == nil)
        #expect(list[1].displayUUID == exact)
        #expect(list[1].spaceUUID == "S")
    }

    // MARK: Bad data

    @Test("Data over 4 MB gives nil")
    func oversizeData() {
        let big = Data(repeating: 0x20, count: LayoutProfileList.maximumDataSize + 1)
        #expect(LayoutProfileList.profiles(from: big) == nil)
        #expect(LayoutProfileList.normalized(big) == nil)
    }

    @Test("A value that is not a list gives nil")
    func notAList() {
        for text in ["{\"name\":\"x\"}", "\"text\"", "12", "null", "not json", ""] {
            #expect(LayoutProfileList.profiles(from: Data(text.utf8)) == nil)
            #expect(LayoutProfileList.normalized(Data(text.utf8)) == nil)
        }
    }

    @Test("One broken element drops only itself")
    func brokenElement() throws {
        let list = try profiles([
            element("Good"),
            ["name": 5, "itemSections": "wrong"],
            ["itemSections": [String: Int]()],
            element("Also good"),
        ])
        #expect(list.map(\.name) == ["Good", "Also good"])
    }

    @Test("An empty list is a list")
    func emptyList() throws {
        #expect(try profiles([]).isEmpty)
        #expect(LayoutProfileList.normalized(Data("[]".utf8)) == Data("[]".utf8))
    }

    // MARK: Settings file

    @Test("A settings file brings only capped profiles")
    func settingsFileProfiles() throws {
        let input = try data((0..<150).map { element("Profile \($0)") })
        let accepted = Defaults.Key.validatedSettings(
            [Defaults.Key.layoutProfiles.rawValue: input],
            ownBundleIdentifier: "com.holzcloud.holzBar"
        )
        let stored = try #require(accepted.accepted[Defaults.Key.layoutProfiles.rawValue] as? Data)
        let list = try #require(LayoutProfileList.profiles(from: stored))
        #expect(list.count == LayoutProfileList.maximumProfiles)
        #expect(accepted.ignored.isEmpty)
    }

    @Test("A LayoutProfiles value that is not a list is removed and reported")
    func settingsFileNotAList() {
        let ownBundle = "com.holzcloud.holzBar"
        for value in [Data("{\"a\":1}".utf8), Data(repeating: 0x20, count: LayoutProfileList.maximumDataSize + 1)] {
            let result = Defaults.Key.validatedSettings(
                [Defaults.Key.layoutProfiles.rawValue: value],
                ownBundleIdentifier: ownBundle
            )
            #expect(result.accepted[Defaults.Key.layoutProfiles.rawValue] == nil)
            #expect(result.ignored.contains(Defaults.Key.layoutProfiles.rawValue))
        }
    }
}
