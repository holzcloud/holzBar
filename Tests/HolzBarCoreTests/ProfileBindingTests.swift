import Testing
@testable import HolzBarCore

@Suite("ProfileBinding")
struct ProfileBindingTests {
    private let work = ProfileBinding.Profile(name: "Work", displayUUID: "D2")
    private let home = ProfileBinding.Profile(name: "Home", spaceUUID: "S1")
    private let plain = ProfileBinding.Profile(name: "Plain")

    @Test("A connected display applies its profile")
    func connectedDisplayAppliesItsProfile() {
        let newlyConnected = ProfileBinding.newlyConnected(previous: ["D1"], current: ["D1", "D2"])
        #expect(newlyConnected == ["D2"])
        #expect(ProfileBinding.profileToApply(
            profiles: [plain, work],
            event: .displaysConnected(newlyConnected, activeSpace: nil),
            currentProfile: nil
        ) == "Work")
        // D2 was already connected: nothing new, nothing applied.
        let nothingNew = ProfileBinding.newlyConnected(previous: ["D1", "D2"], current: ["D1", "D2"])
        #expect(ProfileBinding.profileToApply(
            profiles: [work],
            event: .displaysConnected(nothingNew, activeSpace: nil),
            currentProfile: nil
        ) == nil)
        // Another display is not bound.
        #expect(ProfileBinding.profileToApply(
            profiles: [work],
            event: .displaysConnected(["D3"], activeSpace: nil),
            currentProfile: nil
        ) == nil)
    }

    @Test("A Space applies its profile")
    func spaceAppliesItsProfile() {
        #expect(ProfileBinding.profileToApply(profiles: [work, home], event: .spaceChanged("S1"), currentProfile: nil) == "Home")
        #expect(ProfileBinding.profileToApply(profiles: [work, home], event: .spaceChanged("S2"), currentProfile: nil) == nil)
    }

    @Test("A Space wins over a display")
    func spaceWinsOverDisplay() {
        #expect(ProfileBinding.profileToApply(
            profiles: [work, home],
            event: .displaysConnected(["D2"], activeSpace: "S1"),
            currentProfile: nil
        ) == "Home")
        // Without a bound display, a display change applies nothing.
        #expect(ProfileBinding.profileToApply(
            profiles: [home],
            event: .displaysConnected(["D9"], activeSpace: "S1"),
            currentProfile: nil
        ) == nil)
    }

    @Test("The current profile is not applied again")
    func currentProfileNotAppliedAgain() {
        #expect(ProfileBinding.profileToApply(profiles: [home], event: .spaceChanged("S1"), currentProfile: "Home") == nil)
        #expect(ProfileBinding.profileToApply(
            profiles: [work],
            event: .displaysConnected(["D2"], activeSpace: nil),
            currentProfile: "Work"
        ) == nil)
    }
}
