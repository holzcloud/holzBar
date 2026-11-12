//
//  HotkeysCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable hotkeys of the Hotkeys pane, grouped by goal, in the order the pane shows
    /// them. Item and profile hotkeys are user data and get no entry.
    enum HotkeysPane {
        static let showItems = String(localized: "Show items")
        static let findItems = String(localized: "Find items")
        static let singleItems = String(localized: "Single items")
        static let profiles = String(localized: "Profiles")
        static let modes = String(localized: "Modes")
        static let modules = String(localized: "Modules")

        static let entries: [SettingsEntry] = [
            .hotkeysToggleHidden,
            .hotkeysToggleAlwaysHidden,
            .hotkeysShowForAMoment,
            .hotkeysSearch,
            .hotkeysItemHints,
            .hotkeysCommandPalette,
            .hotkeysShelf,
            .hotkeysAutoRehide,
            .hotkeysZenMode,
            .hotkeysKeepAwake,
            .hotkeysAppMenus,
            .hotkeysNotchHub,
        ]
    }
}

extension SettingsEntry {
    static let hotkeysToggleHidden = SettingsEntry(
        id: "hotkeysToggleHidden",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.showItems,
        label: HotkeyAction.toggleHiddenSection.title,
        info: String(localized: "Opens the holzBar Shelf when it is on.")
    )

    static let hotkeysToggleAlwaysHidden = SettingsEntry(
        id: "hotkeysToggleAlwaysHidden",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.showItems,
        label: HotkeyAction.toggleAlwaysHiddenSection.title
    )

    static let hotkeysShowForAMoment = SettingsEntry(
        id: "hotkeysShowForAMoment",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.showItems,
        label: HotkeyAction.showHiddenSectionTemporarily.title,
        info: String(localized: "Shows them for as long as “Hide opened items again after” in Showing & Hiding says.")
    )

    static let hotkeysSearch = SettingsEntry(
        id: "hotkeysSearch",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.findItems,
        label: HotkeyAction.searchMenuBarItems.title
    )

    static let hotkeysItemHints = SettingsEntry(
        id: "hotkeysItemHints",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.findItems,
        label: HotkeyAction.showItemHints.title,
        info: String(localized: "Shows a letter on every item; the letter opens it.")
    )

    static let hotkeysCommandPalette = SettingsEntry(
        id: "hotkeysCommandPalette",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.findItems,
        label: HotkeyAction.openCommandPalette.title
    )

    static let hotkeysShelf = SettingsEntry(
        id: "hotkeysShelf",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modes,
        label: HotkeyAction.enableShelf.title,
        info: String(localized: "Switches the setting “Use holzBar Shelf”. “Show or hide hidden items” opens the Shelf.")
    )

    static let hotkeysAutoRehide = SettingsEntry(
        id: "hotkeysAutoRehide",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modes,
        label: HotkeyAction.toggleAutoRehide.title
    )

    static let hotkeysZenMode = SettingsEntry(
        id: "hotkeysZenMode",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modes,
        label: HotkeyAction.toggleZenMode.title,
        info: String(localized: "In Zen mode, hidden items stay hidden until you turn it off.")
    )

    static let hotkeysKeepAwake = SettingsEntry(
        id: "hotkeysKeepAwake",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modes,
        label: HotkeyAction.toggleKeepAwake.title
    )

    static let hotkeysAppMenus = SettingsEntry(
        id: "hotkeysAppMenus",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modes,
        label: HotkeyAction.toggleApplicationMenus.title,
        info: String(localized: "Hides or shows the menus of the app in front. While they are hidden, holzBar shows its Dock icon.")
    )

    static let hotkeysNotchHub = SettingsEntry(
        id: "hotkeysNotchHub",
        pane: .hotkeys,
        group: SettingsCatalog.HotkeysPane.modules,
        label: HotkeyAction.toggleNotchHub.title
    )
}
