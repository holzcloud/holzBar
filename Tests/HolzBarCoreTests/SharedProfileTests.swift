import Foundation
import Testing
@testable import HolzBarCore

@Suite("SharedProfile")
struct SharedProfileTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func decode(_ json: String) -> Result<SharedProfile, SharedProfile.Failure> {
        SharedProfile.decode(data(json))
    }

    @Test("A profile survives encoding and decoding")
    func roundTrip() throws {
        let profile = SharedProfile(name: "Work", apps: [
            .init(id: "com.apple.Safari", section: 0),
            .init(id: "com.example.tool", section: 2),
        ])
        let bytes = try #require(profile.encoded())
        #expect(SharedProfile.decode(bytes) == .success(profile))
    }

    @Test("A file that is not a profile is refused")
    func notAProfile() {
        #expect(decode("[]") == .failure(.notAProfile))
        #expect(decode("not json") == .failure(.notAProfile))
        #expect(decode(#"{"format":1,"name":5,"apps":[]}"#) == .failure(.notAProfile))
        #expect(decode(#"{"format":1,"name":"A","apps":[{"id":"com.a.b","section":"x"}]}"#) == .failure(.notAProfile))
        #expect(decode(#"{"format":1,"name":"A","apps":[{"id":"com.a.b","section":1e300}]}"#) == .failure(.notAProfile))
    }

    @Test("An unknown format is refused")
    func unknownFormat() {
        #expect(decode(#"{"format":2,"name":"A","apps":[]}"#) == .failure(.unknownFormat))
    }

    @Test("The name is cleaned and must not be empty")
    func names() throws {
        let result = try #require(try? decode("{\"format\":1,\"name\":\"  Wo\\u0007rk\\n \",\"apps\":[]}").get())
        #expect(result.name == "Work")
        #expect(decode(#"{"format":1,"name":"  ","apps":[]}"#) == .failure(.invalidName))
        let long = String(repeating: "a", count: 200)
        let shortened = try #require(try? decode("{\"format\":1,\"name\":\"\(long)\",\"apps\":[]}").get())
        #expect(shortened.name.count == SharedProfile.maximumNameLength)
    }

    @Test("Bundle identifiers are checked")
    func bundleIdentifiers() {
        #expect(SharedProfile.isValidBundleIdentifier("com.apple.Safari"))
        #expect(SharedProfile.isValidBundleIdentifier("org.example.my-app_2"))
        #expect(!SharedProfile.isValidBundleIdentifier("nodots"))
        #expect(!SharedProfile.isValidBundleIdentifier("com.example/../etc"))
        #expect(!SharedProfile.isValidBundleIdentifier("com.exämple.app"))
        #expect(!SharedProfile.isValidBundleIdentifier("com.a b.c"))
        #expect(!SharedProfile.isValidBundleIdentifier(""))
        #expect(!SharedProfile.isValidBundleIdentifier(String(repeating: "a", count: 300) + ".b"))
        #expect(decode(#"{"format":1,"name":"A","apps":[{"id":"../x","section":0}]}"#) == .failure(.invalidApp))
    }

    @Test("A section outside 0 to 2 is refused")
    func sections() {
        #expect(decode(#"{"format":1,"name":"A","apps":[{"id":"com.a.b","section":3}]}"#) == .failure(.invalidSection))
        #expect(decode(#"{"format":1,"name":"A","apps":[{"id":"com.a.b","section":-1}]}"#) == .failure(.invalidSection))
    }

    @Test("Duplicates keep the first, and extra keys are ignored")
    func duplicates() throws {
        let json = #"{"format":1,"name":"A","extra":{"deep":[1,2]},"apps":[{"id":"com.a.b","section":1},{"id":"com.a.b","section":2}]}"#
        let profile = try #require(try? decode(json).get())
        #expect(profile.apps == [.init(id: "com.a.b", section: 1)])
    }

    @Test("Too large or too many entries are refused")
    func limits() {
        let big = Data(repeating: 0x20, count: SharedProfile.maximumSize + 1)
        #expect(SharedProfile.decode(big) == .failure(.tooLarge))
        let entries = (0...SharedProfile.maximumEntries).map { #"{"id":"com.a.app\#($0)","section":0}"# }
        let json = #"{"format":1,"name":"A","apps":["# + entries.joined(separator: ",") + "]}"
        #expect(decode(json) == .failure(.tooManyApps))
    }

    @Test("The applications of an arrangement come from item keys, application sections and known applications")
    func applications() {
        let entries = SharedProfile.applications(
            itemSections: [
                "com.apple.Safari:Safari": 1,
                "com.apple.Safari:Safari 2": 2,
                "7E1A3C52-0000-0000-0000-000000000000:Item-0": 1,
                "com.example.tool:Tool": 2,
            ],
            applicationSections: ["com.example.other": 1],
            knownApplications: ["com.example.other", "com.example.visible"]
        )
        #expect(entries == [
            .init(id: "com.apple.Safari", section: 1),
            .init(id: "com.example.other", section: 1),
            .init(id: "com.example.tool", section: 2),
            .init(id: "com.example.visible", section: 0),
        ])
    }

    @Test("A name clash gets a number")
    func uniqueNames() {
        #expect(SharedProfile.uniqueName("Work", among: ["Home"]) == "Work")
        #expect(SharedProfile.uniqueName("Work", among: ["Work"]) == "Work 2")
        #expect(SharedProfile.uniqueName("Work", among: ["Work", "Work 2"]) == "Work 3")
    }
}
