//
//  ShelfCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the holzBar Shelf pane, in the order the pane shows them.
    enum ShelfPane {
        /// The untitled first group; search results name it after the pane.
        static let firstGroup = String(localized: "holzBar Shelf")
        static let look = String(localized: "Look")
        static let useOn = String(localized: "Use on")
        static let moreOptions = String(localized: "More options")
        /// The id of the pane's one disclosure (D-20); not a user-visible string.
        static let moreOptionsID = "shelf.moreOptions"

        static let entries: [SettingsEntry] = [
            .shelfUse,
            .shelfStyle,
            .shelfLayout,
            .shelfDisplays,
            .shelfNotchOverflow,
            .shelfLocation,
            .shelfFindsByTyping,
            .shelfAlwaysHiddenFold,
            .shelfShowsClosedApps,
            .shelfDragsTiles,
        ]
    }
}

extension SettingsEntry {
    static let shelfUse = SettingsEntry(
        id: "shelfUse",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.firstGroup,
        label: String(localized: "Use holzBar Shelf"),
        info: String(localized: "Shows hidden menu bar items in a separate bar under the menu bar.")
    )

    static let shelfStyle = SettingsEntry(
        id: "shelfStyle",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.look,
        label: String(localized: "Style"),
        info: String(localized: "Attached hangs directly under the menu bar; Floating floats a little apart, as a bar of its own.")
    )

    static let shelfLayout = SettingsEntry(
        id: "shelfLayout",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.look,
        label: String(localized: "Layout"),
        info: String(localized: "A row holds every item side by side. A grid and a column hold more items without scrolling.")
    )

    static let shelfDisplays = SettingsEntry(
        id: "shelfDisplays",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.useOn,
        label: String(localized: "Use holzBar Shelf on"),
        info: String(localized: "On other displays, hidden menu bar items are shown in the menu bar itself.")
    )

    static let shelfNotchOverflow = SettingsEntry(
        id: "shelfNotchOverflow",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.useOn,
        label: String(localized: "Show items covered by the notch"),
        info: String(localized: "Visible items the notch hides, for example behind a long app menu, also appear in the holzBar Shelf. On macOS 27, items in macOS's own overflow are left out.")
    )

    static let shelfLocation = SettingsEntry(
        id: "shelfLocation",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.moreOptions,
        label: String(localized: "Location"),
        info: String(localized: "Dynamic, under the mouse pointer, under the holzBar icon or at the right edge of the screen."),
        disclosure: SettingsCatalog.ShelfPane.moreOptionsID
    )

    static let shelfFindsByTyping = SettingsEntry(
        id: "shelfFindsByTyping",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.moreOptions,
        label: String(localized: "Find items by typing"),
        info: String(localized: "Type in the holzBar Shelf to highlight the best match. Return opens its menu and Escape closes the holzBar Shelf. The holzBar Shelf takes the keyboard when a hotkey opens it."),
        disclosure: SettingsCatalog.ShelfPane.moreOptionsID
    )

    static let shelfAlwaysHiddenFold = SettingsEntry(
        id: "shelfAlwaysHiddenFold",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.moreOptions,
        label: String(localized: "Always-hidden items"),
        info: String(localized: "The holzBar Shelf shows the always-hidden items behind one tile. Click the tile to open them."),
        disclosure: SettingsCatalog.ShelfPane.moreOptionsID
    )

    static let shelfShowsClosedApps = SettingsEntry(
        id: "shelfShowsClosedApps",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.moreOptions,
        label: String(localized: "Show apps that are not running"),
        info: String(localized: "Applications with a hidden item that are closed appear dimmed in the holzBar Shelf. Click one to open it."),
        disclosure: SettingsCatalog.ShelfPane.moreOptionsID
    )

    static let shelfDragsTiles = SettingsEntry(
        id: "shelfDragsTiles",
        pane: .shelf,
        group: SettingsCatalog.ShelfPane.moreOptions,
        label: String(localized: "Rearrange items by dragging"),
        info: String(localized: "Drag an item in the holzBar Shelf to another place, into another section or up onto the menu bar. Where macOS orders a section itself, only the section can change."),
        disclosure: SettingsCatalog.ShelfPane.moreOptionsID
    )
}
