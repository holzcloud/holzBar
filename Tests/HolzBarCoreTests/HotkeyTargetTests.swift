import Testing
@testable import HolzBarCore

@Suite("HotkeyTarget")
struct HotkeyTargetTests {
    @Test("Actions keep their stored names")
    func actionsKeepTheirStoredNames() {
        #expect(HotkeyTarget.action(.toggleHiddenSection).storageKey == "ToggleHiddenSection")
        #expect(HotkeyTarget.action(.enableShelf).storageKey == "EnableIceBar")
        for action in HotkeyAction.allCases {
            let target = HotkeyTarget.action(action)
            #expect(HotkeyTarget(storageKey: target.storageKey) == target)
            #expect(!target.isDynamic)
        }
    }

    @Test("Profiles and items have prefixed keys")
    func profilesAndItemsHavePrefixedKeys() {
        let profile = HotkeyTarget.applyProfile("Work")
        let item = HotkeyTarget.openItem("com.example:#1")
        #expect(profile.storageKey == "ApplyProfile:Work")
        #expect(item.storageKey == "OpenItem:com.example:#1")
        #expect(HotkeyTarget(storageKey: "ApplyProfile:Work") == profile)
        #expect(HotkeyTarget(storageKey: "OpenItem:com.example:#1") == item)
        #expect(HotkeyTarget(storageKey: "ApplyProfile:My Work: Home") == .applyProfile("My Work: Home"))
        #expect(profile.isDynamic)
        #expect(item.isDynamic)
    }

    @Test("Unknown and empty keys name nothing")
    func unknownKeysNameNothing() {
        #expect(HotkeyTarget(storageKey: "LaunchRockets") == nil)
        #expect(HotkeyTarget(storageKey: "ApplyProfile:") == nil)
        #expect(HotkeyTarget(storageKey: "OpenItem:") == nil)
        #expect(HotkeyTarget(storageKey: "") == nil)
    }

    @Test("The log names no profile and no item")
    func logNamesNoProfileOrItem() {
        #expect(!HotkeyTarget.applyProfile("Secret").logDescription.contains("Secret"))
        #expect(!HotkeyTarget.openItem("com.example:#1").logDescription.contains("example"))
        #expect(HotkeyTarget.action(.toggleZenMode).logDescription == "ToggleZenMode")
    }
}
