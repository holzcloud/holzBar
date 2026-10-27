import Testing

@testable import HolzBarCore

@Suite("MenuBarIconChoice")
struct MenuBarIconChoiceTests {
    @Test("With the icon shown, the card of its style is selected")
    func shown() {
        #expect(MenuBarIconChoice.current(showsIcon: true, styleName: "Eye") == .style("Eye"))
    }

    @Test("With the icon off, the card for no icon is selected whatever style is stored")
    func hidden() {
        #expect(MenuBarIconChoice.current(showsIcon: false, styleName: "Eye") == .none)
        #expect(MenuBarIconChoice.current(showsIcon: false, styleName: "Custom") == .none)
    }

    @Test("A style shows the icon and stores its name")
    func styleChoice() {
        let choice = MenuBarIconChoice.style("Grid")
        #expect(choice.showsIcon)
        #expect(choice.styleName == "Grid")
    }

    @Test("No icon hides the icon and leaves the stored style alone")
    func noneChoice() {
        #expect(!MenuBarIconChoice.none.showsIcon)
        #expect(MenuBarIconChoice.none.styleName == nil)
    }

    @Test("Choosing a style again after no icon brings the icon back")
    func roundTrip() {
        var showsIcon = true
        var styleName = "Chevron"
        for choice in [MenuBarIconChoice.none, .style("Panel")] {
            showsIcon = choice.showsIcon
            if let name = choice.styleName {
                styleName = name
            }
        }
        #expect(MenuBarIconChoice.current(showsIcon: showsIcon, styleName: styleName) == .style("Panel"))
    }
}

@Suite("SettingsAccess")
struct SettingsAccessTests {
    @Test("Without any hotkey, reopening the app and the link remain")
    func baseline() {
        let ways = SettingsAccess.ways(hasSearchHotkey: false, hasCommandPaletteHotkey: false)
        #expect(ways == [.reopenApp, .link])
    }

    @Test("A way remains whatever hotkeys are set")
    func alwaysAWay() {
        for search in [true, false] {
            for palette in [true, false] {
                let ways = SettingsAccess.ways(hasSearchHotkey: search, hasCommandPaletteHotkey: palette)
                #expect(ways.contains(.reopenApp))
                #expect(!ways.isEmpty)
            }
        }
    }

    @Test("The search and the command palette count only with their hotkey")
    func hotkeys() {
        let search = SettingsAccess.ways(hasSearchHotkey: true, hasCommandPaletteHotkey: false)
        #expect(search.contains(.searchPanel))
        #expect(!search.contains(.commandPalette))
        let palette = SettingsAccess.ways(hasSearchHotkey: false, hasCommandPaletteHotkey: true)
        #expect(palette.contains(.commandPalette))
        #expect(!palette.contains(.searchPanel))
        let both = SettingsAccess.ways(hasSearchHotkey: true, hasCommandPaletteHotkey: true)
        #expect(Set(both) == Set(SettingsAccess.Way.allCases))
    }
}
