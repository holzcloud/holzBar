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

    @Test("A list of more than 100 profiles loads in full")
    func moreThanAddLimitLoads() throws {
        let list = try profiles((0..<150).map { element("Profile \($0)") })
        #expect(list.count == 150)
        #expect(LayoutProfileList.maximumProfiles == 100)
    }

    @Test("At most 1000 profiles are kept, the first ones")
    func profileCap() throws {
        let elements = (0..<1200).map { element("Profile \($0)", items: [:], apps: [:]) }
        let list = try profiles(elements)
        #expect(LayoutProfileList.maximumStoredProfiles == 1000)
        #expect(list.count == LayoutProfileList.maximumStoredProfiles)
        #expect(list.first?.name == "Profile 0")
        #expect(list.last?.name == "Profile 999")
    }

    @Test("A name an earlier profile has gets a number instead of being dropped")
    func duplicateNames() throws {
        let list = try profiles([
            element("Work", items: ["a": 0]),
            element("Work", items: ["b": 0]),
            element("Work 2", items: ["c": 0]),
            element("Work", items: ["d": 0]),
            element("work"),
        ])
        // A real stored name is never taken by a numbered repeat.
        #expect(list.map(\.name) == ["Work", "Work 3", "Work 2", "Work 4", "work"])
        #expect(list.map(\.itemSections) == [["a": 0], ["b": 0], ["c": 0], ["d": 0], ["com.example.app:Item": 1]])
    }

    @Test("Numbering a repeat skips every real stored name")
    func numberingSkipsRealNames() throws {
        let list = try profiles([element("Work"), element("Work"), element("Work 2")])
        #expect(list.map(\.name) == ["Work", "Work 3", "Work 2"])
    }

    @Test("A name that is empty or white space is dropped")
    func emptyNames() throws {
        let list = try profiles([element(""), element("   "), element("\n\t"), element("Real")])
        #expect(list.map(\.name) == ["Real"])
    }

    @Test("A stored name is kept exactly, even where a typed one would be cleaned")
    func storedNamesKeptExactly() throws {
        let emoji = "\u{1F469}\u{200D}\u{1F4BB} Work"
        let long = String(repeating: "x", count: SharedProfile.maximumNameLength + 1)
        let marked = "Wo\u{00AD}rk \u{200E}"
        let list = try profiles([element(emoji), element(long), element(marked), element(" Spaced ")])
        #expect(list.map(\.name) == [emoji, long, marked, " Spaced "])
        // Typed names are still cleaned.
        #expect(LayoutProfileList.cleanedName(" Wo\u{0007}rk\n") == "Work")
        #expect(LayoutProfileList.cleanedName(long).count == SharedProfile.maximumNameLength)
    }

    @Test("Profiles that differ only after cleaning both stay")
    func cleaningDoesNotCollapse() throws {
        let list = try profiles([element("Work"), element("Wo\u{200B}rk"), element(String(repeating: "y", count: 81)), element(String(repeating: "y", count: 82))])
        #expect(list.count == 4)
        #expect(Set(list.map(\.name)).count == 4)
    }

    @Test("A stored name over the byte cap is dropped")
    func nameByteCap() throws {
        let exact = String(repeating: "n", count: LayoutProfileList.maximumStoredNameBytes)
        let over = exact + "n"
        let list = try profiles([element(over), element(exact)])
        #expect(list.map(\.name) == [exact])
    }

    @Test("A name cut inside a space does not end in one")
    func cutNameHasNoTrailingSpace() {
        let name = String(repeating: "a", count: 79) + " b"
        let cleaned = LayoutProfileList.cleanedName(name)
        #expect(cleaned == String(repeating: "a", count: 79))
        #expect(LayoutProfileList.cleanedName(cleaned) == cleaned)
    }

    @Test("A typed name that is a stored name, exactly or once cleaned, refers to that profile")
    func typedNameMatchesStoredName() {
        let emoji = "\u{1F469}\u{200D}\u{1F4BB} Work"
        let hyphen = "Wo\u{00AD}rk"
        let long = String(repeating: "x", count: 90)
        let names = [emoji, hyphen, long, "Home"]
        // The pre-filled stored name keeps the profile's identity.
        #expect(LayoutProfileList.savedName(forTyped: emoji, among: names) == emoji)
        #expect(LayoutProfileList.savedName(forTyped: " \(hyphen) ", among: names) == hyphen)
        #expect(LayoutProfileList.savedName(forTyped: long, among: names) == long)
        // The cleaned form of a stored name refers to it too.
        #expect(LayoutProfileList.savedName(forTyped: LayoutProfileList.cleanedName(emoji), among: names) == emoji)
        #expect(LayoutProfileList.savedName(forTyped: "Work", among: [hyphen]) == hyphen)
        // An exact match wins over a cleaned one.
        #expect(LayoutProfileList.savedName(forTyped: "Work", among: [hyphen, "Work"]) == "Work")
        // A new name is cleaned.
        #expect(LayoutProfileList.savedName(forTyped: " Ne\u{0007}w ", among: names) == "New")
        #expect(LayoutProfileList.existingName(matching: "New", among: names) == nil)
        #expect(LayoutProfileList.existingName(matching: "   ", among: names) == nil)
    }

    @Test("A limit that a list breaks is named; 100 is the limit for adding only")
    func limitViolation() {
        func list(_ count: Int) -> [LayoutProfile] {
            (0..<count).map { LayoutProfile(name: "P\($0)", itemSections: [:], applicationSections: [:]) }
        }
        #expect(LayoutProfileList.limitViolation(list(100), adding: true) == nil)
        #expect(LayoutProfileList.limitViolation(list(101), adding: true) == .tooMany)
        // Replacing or renaming in a list above 100 keeps working.
        #expect(LayoutProfileList.limitViolation(list(150)) == nil)
        #expect(LayoutProfileList.limitViolation(list(150), adding: true) == .tooMany)
        #expect(LayoutProfileList.limitViolation(list(LayoutProfileList.maximumStoredProfiles)) == nil)
        #expect(LayoutProfileList.limitViolation(list(LayoutProfileList.maximumStoredProfiles + 1)) == .tooMany)
        let key = String(repeating: "k", count: 500)
        let heavy = LayoutProfile(
            name: "Heavy",
            itemSections: Dictionary(uniqueKeysWithValues: (0..<9000).map { ("\($0)\(key)", 1) }),
            applicationSections: [:]
        )
        #expect(LayoutProfileList.limitViolation([heavy]) == .tooLarge)
        #expect(LayoutProfileList.limitViolation([heavy], adding: true) == .tooLarge)
    }

    @Test("A list the app stores loads again in full")
    func fitsLimits() throws {
        let many = (0..<150).map {
            LayoutProfile(name: "Profile \($0)", itemSections: ["a": 1], applicationSections: [:])
        }
        #expect(LayoutProfileList.fitsLimits([]))
        #expect(LayoutProfileList.fitsLimits(many))
        #expect(!LayoutProfileList.fitsLimits(many, adding: true))
        #expect(LayoutProfileList.fitsLimits(Array(many.prefix(99)), adding: true))
        // What fits is what the next load keeps.
        let data = try #require(LayoutProfileList.encoded(many))
        #expect(LayoutProfileList.profiles(from: data) == many)
        // Over 4 MB once encoded.
        let key = String(repeating: "k", count: 500)
        let big = (0..<9000).map { "\($0)\(key)" }
        let heavy = LayoutProfile(
            name: "Heavy",
            itemSections: Dictionary(uniqueKeysWithValues: big.map { ($0, 1) }),
            applicationSections: [:]
        )
        #expect(!LayoutProfileList.fitsLimits([heavy]))
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
        let input = try data((0..<1200).map { element("Profile \($0)", items: [:], apps: [:]) })
        let accepted = Defaults.Key.validatedSettings(
            [Defaults.Key.layoutProfiles.rawValue: input],
            ownBundleIdentifier: "com.holzcloud.holzBar"
        )
        let stored = try #require(accepted.accepted[Defaults.Key.layoutProfiles.rawValue] as? Data)
        let list = try #require(LayoutProfileList.profiles(from: stored))
        #expect(list.count == LayoutProfileList.maximumStoredProfiles)
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
