import Foundation
import Testing
@testable import HolzBarCore

@Suite("ProfileIdentity")
struct ProfileIdentityTests {
    private func profilesJSON(_ names: [String], extra: [String: Any] = [:]) throws -> Data {
        let objects: [[String: Any]] = names.map { name in
            var object: [String: Any] = [
                "name": name,
                "itemSections": ["com.example:#1": 1],
                "applicationSections": [String: Int](),
            ]
            for (key, value) in extra {
                object[key] = value
            }
            return object
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }

    private func decode(_ data: Data?) throws -> [[String: Any]] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("Legacy IDs are stable uppercase version 8 UUIDs that differ by name")
    func legacyIDsAreStable() throws {
        let work = ProfileIdentity.legacyProfileID(forName: "Work")
        #expect(work == ProfileIdentity.legacyProfileID(forName: "Work"))
        #expect(work != ProfileIdentity.legacyProfileID(forName: "Home"))
        #expect(work != ProfileIdentity.legacyProfileID(forName: "work"))
        #expect(work == work.uppercased())
        let uuid = try #require(UUID(uuidString: work))
        #expect(uuid.uuidString == work)
        let parts = work.split(separator: "-")
        #expect(parts[2].first == "8")
        #expect("89AB".contains(try #require(parts[3].first)))
    }

    @Test("New IDs are random UUIDs")
    func newIDsAreRandom() {
        let first = ProfileIdentity.newProfileID()
        #expect(UUID(uuidString: first) != nil)
        #expect(first != ProfileIdentity.newProfileID())
    }

    @Test("Two Macs with the same profiles get the same IDs")
    func twoMacsAgree() throws {
        let macA = ProfileIdentity.migrate(profilesData: try profilesJSON(["Work", "Home"]), hotkeys: [:])
        let macB = ProfileIdentity.migrate(profilesData: try profilesJSON(["Home", "Work"]), hotkeys: [:])
        #expect(macA.changed)
        let idsA = Dictionary(uniqueKeysWithValues: try decode(macA.profilesData).map { ($0["name"] as? String ?? "", $0["profileID"] as? String ?? "") })
        let idsB = Dictionary(uniqueKeysWithValues: try decode(macB.profilesData).map { ($0["name"] as? String ?? "", $0["profileID"] as? String ?? "") })
        #expect(idsA == idsB)
        #expect(idsA["Work"] == ProfileIdentity.legacyProfileID(forName: "Work"))
    }

    @Test("Unknown JSON fields survive")
    func unknownFieldsSurvive() throws {
        let data = try profilesJSON(["Work"], extra: ["futureField": ["a": 1], "displayUUID": "D-1"])
        let result = ProfileIdentity.migrate(profilesData: data, hotkeys: [:])
        let profile = try #require(try decode(result.profilesData).first)
        #expect(profile["futureField"] as? [String: Int] == ["a": 1])
        #expect(profile["displayUUID"] as? String == "D-1")
        #expect(profile["itemSections"] as? [String: Int] == ["com.example:#1": 1])
        #expect(profile["profileID"] as? String == ProfileIdentity.legacyProfileID(forName: "Work"))
    }

    @Test("A profile's hotkey is re-keyed, an unknown name's is not")
    func hotkeysAreRekeyed() throws {
        let work = Data("work".utf8)
        let stray = Data("stray".utf8)
        let action = Data("action".utf8)
        let result = ProfileIdentity.migrate(
            profilesData: try profilesJSON(["Work"]),
            hotkeys: ["ApplyProfile:Work": work, "ApplyProfile:Gone": stray, "ToggleHiddenSection": action]
        )
        let id = ProfileIdentity.legacyProfileID(forName: "Work")
        #expect(result.hotkeys == ["ApplyProfile:\(id)": work, "ApplyProfile:Gone": stray, "ToggleHiddenSection": action])
        #expect(result.changed)
    }

    @Test("Profiles that already have IDs still get their hotkeys re-keyed")
    func rekeysHotkeysOfProfilesWithIDs() throws {
        let data = try profilesJSON(["Work"], extra: ["profileID": "ID-1"])
        let result = ProfileIdentity.migrate(profilesData: data, hotkeys: ["ApplyProfile:Work": Data("k".utf8)])
        #expect(result.changed)
        #expect(result.profilesData == data)
        #expect(result.hotkeys == ["ApplyProfile:ID-1": Data("k".utf8)])
    }

    @Test("Duplicate names get distinct deterministic IDs")
    func duplicateNames() throws {
        let result = ProfileIdentity.migrate(profilesData: try profilesJSON(["Work", "Work", "Work"]), hotkeys: [:])
        let ids = try decode(result.profilesData).compactMap { $0["profileID"] as? String }
        #expect(Set(ids).count == 3)
        #expect(ids[0] == ProfileIdentity.legacyProfileID(forName: "Work"))
        #expect(ids[1] == ProfileIdentity.legacyProfileID(forName: "Work#2"))
        #expect(ids[2] == ProfileIdentity.legacyProfileID(forName: "Work#3"))
    }

    @Test("The second run changes nothing")
    func secondRunChangesNothing() throws {
        let first = ProfileIdentity.migrate(
            profilesData: try profilesJSON(["Work", "Home"]),
            hotkeys: ["ApplyProfile:Work": Data("k".utf8)]
        )
        #expect(first.changed)
        let second = ProfileIdentity.migrate(profilesData: first.profilesData, hotkeys: first.hotkeys)
        #expect(!second.changed)
        #expect(second.profilesData == first.profilesData)
        #expect(second.hotkeys == first.hotkeys)
    }

    @Test("Malformed or missing data stays as it is")
    func malformedData() {
        let hotkeys = ["ApplyProfile:Work": Data("k".utf8)]
        for data in [nil, Data(), Data("not json".utf8), Data("{\"name\":\"Work\"}".utf8), Data("[1,2]".utf8)] {
            let result = ProfileIdentity.migrate(profilesData: data, hotkeys: hotkeys)
            #expect(!result.changed)
            #expect(result.profilesData == data)
            #expect(result.hotkeys == hotkeys)
        }
    }
}
