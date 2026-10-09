import Testing
@testable import HolzBarCore

@Suite("FocusFilterBinding")
struct FocusFilterBindingTests {
    @Test("A Focus that turns on applies its profile")
    func appliesProfile() {
        var binding = FocusFilterBinding()
        #expect(binding.profileToApply(requested: "Work", current: "Home") == "Work")
        #expect(binding.applied == "Work")
        #expect(binding.previous == "Home")
    }

    @Test("The profile that is already applied is not applied again")
    func skipsActiveProfile() {
        var binding = FocusFilterBinding()
        #expect(binding.profileToApply(requested: "Work", current: "Work") == nil)
        #expect(binding.applied == "Work")
    }

    @Test("The previous profile comes back when the Focus ends")
    func restoresPrevious() {
        var binding = FocusFilterBinding()
        _ = binding.profileToApply(requested: "Work", current: "Home")
        #expect(binding.profileToApply(requested: nil, current: "Work") == "Home")
        #expect(binding.applied == nil)
        #expect(binding.previous == nil)
    }

    @Test("A profile the user chose meanwhile is left alone")
    func respectsUserChange() {
        var binding = FocusFilterBinding()
        _ = binding.profileToApply(requested: "Work", current: "Home")
        #expect(binding.profileToApply(requested: nil, current: "Travel") == nil)
    }

    @Test("A Focus that never applied anything restores nothing")
    func endWithoutStart() {
        var binding = FocusFilterBinding()
        #expect(binding.profileToApply(requested: nil, current: "Home") == nil)
    }

    @Test("One Focus replacing another keeps the profile from before the first")
    func focusReplacesFocus() {
        var binding = FocusFilterBinding()
        _ = binding.profileToApply(requested: "Work", current: "Home")
        #expect(binding.profileToApply(requested: "Sleep", current: "Work") == "Sleep")
        #expect(binding.profileToApply(requested: nil, current: "Sleep") == "Home")
    }

    @Test("Nothing to go back to when no profile was applied before")
    func noPreviousProfile() {
        var binding = FocusFilterBinding()
        _ = binding.profileToApply(requested: "Work", current: nil)
        #expect(binding.profileToApply(requested: nil, current: "Work") == nil)
    }
}
