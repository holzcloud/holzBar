//
//  ShowingAndHidingCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Showing & Hiding pane, in the order the pane shows them.
    enum ShowingAndHidingPane {
        static let showHiddenItems = String(localized: "Show hidden items")
        static let hideAgain = String(localized: "Hide again")
        static let displays = String(localized: "Displays")
        static let zenModeAndLock = String(localized: "Zen mode and lock")
        static let animation = String(localized: "Animation")

        static let entries: [SettingsEntry] = [
            .hidingShowOnClick,
            .hidingShowOnHover,
            .hidingHoverDelay,
            .hidingShowOnScroll,
            .hidingOpenInMenuBar,
        ]
    }
}

extension SettingsEntry {
    static let hidingShowOnClick = SettingsEntry(
        id: "hidingShowOnClick",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on click"),
        info: String(localized: "Click inside an empty area of the menu bar to show hidden menu bar items.")
    )

    static let hidingShowOnHover = SettingsEntry(
        id: "hidingShowOnHover",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on hover"),
        info: String(localized: "Hover over an empty area of the menu bar to show hidden menu bar items.")
    )

    static let hidingHoverDelay = SettingsEntry(
        id: "hidingHoverDelay",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Hover delay"),
        info: String(localized: "How long holzBar waits before hovering shows the hidden items, from 0 to 1 second.")
    )

    static let hidingShowOnScroll = SettingsEntry(
        id: "hidingShowOnScroll",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on scroll"),
        info: String(localized: "Scroll or swipe in the menu bar to show hidden menu bar items.")
    )

    static let hidingOpenInMenuBar = SettingsEntry(
        id: "hidingOpenInMenuBar",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Open hidden items in the menu bar"),
        info: String(localized: "Shows a hidden item in the menu bar and opens its menu under it. Off, the menu opens without showing the item.")
    )
}
