import Foundation
import Testing
@testable import HolzBarCore

@Suite("ControlCenterControl")
struct ControlCenterControlTests {
    private let screenshot = ":com.apple.screenshot.launcher:com.apple.controls.screenshot:com.apple.controls.screenshot.capture-custom"
    private let uuid = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private let otherUUID = "0E984725-C51C-4BF4-9960-E1C80E27ABA0"

    @Test("A pinned control title has an empty first and three filled components")
    func pinnedControlShape() {
        #expect(ControlCenterControl.isPinnedControlTitle(screenshot))
        #expect(ControlCenterControl.isPinnedControlTitle("\(screenshot):\(uuid)"))
    }

    @Test("Other titles are not pinned controls")
    func otherTitlesAreNot() {
        #expect(!ControlCenterControl.isPinnedControlTitle("com.apple.menuextra.clock"))
        #expect(!ControlCenterControl.isPinnedControlTitle(""))
        // No leading colon.
        #expect(!ControlCenterControl.isPinnedControlTitle("a:b:c:d"))
        // An empty middle component.
        #expect(!ControlCenterControl.isPinnedControlTitle(":a::c"))
        #expect(!ControlCenterControl.isPinnedControlTitle(":a:b:"))
        // Three and six components.
        #expect(!ControlCenterControl.isPinnedControlTitle(":a:b"))
        #expect(!ControlCenterControl.isPinnedControlTitle("\(screenshot):\(uuid):extra"))
        // A fifth component that is not a UUID.
        #expect(!ControlCenterControl.isPinnedControlTitle("\(screenshot):not-a-uuid"))
    }

    @Test("Only a MenuBarAgent item with the shape is a pinned control")
    func namespaceIsChecked() {
        #expect(ControlCenterControl.isPinnedControl(namespace: "com.apple.MenuBarAgent", title: screenshot))
        #expect(ControlCenterControl.isPinnedControl(namespace: "com.apple.MenuBarAgent", title: "\(screenshot):\(uuid)"))
        // An app cannot make its item fixed by naming it like a control (T-86-08).
        #expect(!ControlCenterControl.isPinnedControl(namespace: "com.example.app", title: screenshot))
        #expect(!ControlCenterControl.isPinnedControl(namespace: "com.apple.MenuBarAgent", title: "com.apple.menuextra.clock"))
    }

    @Test("The instance UUID is not part of the identity")
    func stableIdentityDropsTheUUID() {
        #expect(ControlCenterControl.stableIdentity(forTitle: "\(screenshot):\(uuid)") == screenshot)
        #expect(ControlCenterControl.stableIdentity(forTitle: "\(screenshot):\(otherUUID)") == screenshot)
        #expect(ControlCenterControl.stableIdentity(forTitle: screenshot) == screenshot)
        #expect(ControlCenterControl.stableIdentity(forTitle: "Mail 3") == "Mail 3")
        #expect(ControlCenterControl.stableIdentity(forTitle: "com.apple.menuextra.clock") == "com.apple.menuextra.clock")
        #expect(ControlCenterControl.stableIdentity(forTitle: "") == "")
    }
}
