import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsPaneID")
struct SettingsPaneIDTests {
    @Test("The eleven panes come in the approved sidebar order")
    func order() {
        #expect(SettingsPaneID.allCases == [
            .layout, .showingAndHiding, .shelf, .profilesAndHistory, .appearance, .automation,
            .modules, .general, .hotkeys, .advanced, .about
        ])
    }

    @Test("The three sidebar groups together are all panes, once")
    func groupsCoverAllPanes() {
        let all = SettingsPaneID.menuBarGroup + SettingsPaneID.modulesGroup + SettingsPaneID.appGroup
        #expect(all == SettingsPaneID.allCases)
        #expect(SettingsPaneID.menuBarGroup == [
            .layout, .showingAndHiding, .shelf, .profilesAndHistory, .appearance, .automation
        ])
        #expect(SettingsPaneID.modulesGroup == [.modules])
        #expect(SettingsPaneID.appGroup == [.general, .hotkeys, .advanced, .about])
    }

    @Test("Each pane has its symbol, and About uses the logo")
    func symbols() {
        #expect(SettingsPaneID.layout.symbolName == "menubar.rectangle")
        #expect(SettingsPaneID.showingAndHiding.symbolName == "eye")
        #expect(SettingsPaneID.shelf.symbolName == "tray")
        #expect(SettingsPaneID.profilesAndHistory.symbolName == "clock.arrow.circlepath")
        #expect(SettingsPaneID.appearance.symbolName == "paintbrush.pointed")
        #expect(SettingsPaneID.automation.symbolName == "bolt.badge.automatic")
        #expect(SettingsPaneID.modules.symbolName == "puzzlepiece.extension")
        #expect(SettingsPaneID.general.symbolName == "switch.2")
        #expect(SettingsPaneID.hotkeys.symbolName == "command")
        #expect(SettingsPaneID.advanced.symbolName == "wrench.and.screwdriver")
        #expect(SettingsPaneID.about.symbolName == nil)
    }
}
