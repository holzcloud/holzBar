import Testing
@testable import HolzBarCore

@Suite("DockIconPolicy")
struct DockIconPolicyTests {
    @Test("Settings and search stay out of the Dock")
    func settingsAndSearchStayOutOfTheDock() {
        for keepsHidden in [true, false] {
            #expect(DockIconPolicy.policy(for: .settings, keepsDockIconHidden: keepsHidden) == .accessory)
            #expect(DockIconPolicy.policy(for: .search, keepsDockIconHidden: keepsHidden) == .accessory)
        }
    }

    @Test("The permissions window is in the Dock")
    func permissionsWindowIsInTheDock() {
        #expect(DockIconPolicy.policy(for: .permissions, keepsDockIconHidden: true) == .regular)
        #expect(DockIconPolicy.policy(for: .permissions, keepsDockIconHidden: false) == .regular)
    }

    @Test("Hiding application menus needs the Dock icon, so it waits for the setting")
    func hidingApplicationMenusFollowsTheSetting() {
        #expect(DockIconPolicy.policy(for: .hideApplicationMenus, keepsDockIconHidden: false) == .regular)
        #expect(DockIconPolicy.policy(for: .hideApplicationMenus, keepsDockIconHidden: true) == nil)
    }

    @Test("Hiding the menus on request brings the Dock icon")
    func hidingMenusOnRequestBringsTheDockIcon() {
        #expect(DockIconPolicy.policy(for: .toggleApplicationMenus, keepsDockIconHidden: true) == .regular)
        #expect(DockIconPolicy.policy(for: .toggleApplicationMenus, keepsDockIconHidden: false) == .regular)
    }
}
