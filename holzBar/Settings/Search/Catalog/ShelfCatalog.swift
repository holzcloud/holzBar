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

        static let entries: [SettingsEntry] = [.shelfUse]
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
}
