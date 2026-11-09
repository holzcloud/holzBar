import Testing
@testable import HolzBarCore

@Suite("LayoutProfile")
struct LayoutProfileTests {
    // MARK: A partial change

    @Test("A partial change knows exactly the applications it moves")
    func partialChangeKnowsItsApplications() {
        let change = LayoutProfile.partialChange(
            itemSections: ["com.b.app:Item": 1],
            applicationSections: ["com.b.app": 1, "com.a.app": 0]
        )
        #expect(change.name.isEmpty)
        #expect(change.itemSections == ["com.b.app:Item": 1])
        #expect(change.applicationSections == ["com.b.app": 1, "com.a.app": 0])
        #expect(change.knownApplications == ["com.a.app", "com.b.app"])
        #expect(change.displayUUID == nil)
        #expect(change.spaceUUID == nil)
    }

    @Test("A partial change without applications knows none, which is not the same as nil")
    func emptyPartialChangeKnowsNothing() {
        let change = LayoutProfile.partialChange(itemSections: ["com.b.app:Item": 2], applicationSections: [:])
        #expect(change.knownApplications == [])
        #expect(change.knownApplications != nil)
    }

    // MARK: Leaving applications out

    @Test("Leaving an application out drops it from the sections and from the known ones")
    func removingDropsSectionAndKnown() {
        let profile = LayoutProfile(
            name: "Home",
            itemSections: ["com.r.app:Item": 1, "com.b.app:Item": 1],
            applicationSections: ["com.r.app": 1, "com.b.app": 2],
            knownApplications: ["com.b.app", "com.r.app", "com.v.app"],
            displayUUID: "D-1"
        )
        let result = profile.removingApplications(["com.r.app"])
        #expect(result.applicationSections == ["com.b.app": 2])
        #expect(result.knownApplications == ["com.b.app", "com.v.app"])
        #expect(result.itemSections == profile.itemSections)
        #expect(result.name == "Home")
        #expect(result.displayUUID == "D-1")
    }

    @Test("A profile that recorded no applications keeps recording none")
    func removingKeepsNilKnown() {
        let profile = LayoutProfile(name: "Old", itemSections: [:], applicationSections: ["com.r.app": 1, "com.b.app": 1])
        let result = profile.removingApplications(["com.r.app"])
        #expect(result.knownApplications == nil)
        #expect(result.applicationSections == ["com.b.app": 1])
    }

    @Test("A profile without the application stays as it is")
    func removingAbsentChangesNothing() {
        let profile = LayoutProfile(
            name: "Work",
            itemSections: ["com.b.app:Item": 0],
            applicationSections: ["com.b.app": 1],
            knownApplications: ["com.b.app"]
        )
        #expect(profile.removingApplications(["com.r.app"]) == profile)
        #expect(profile.removingApplications([]) == profile)
    }
}
