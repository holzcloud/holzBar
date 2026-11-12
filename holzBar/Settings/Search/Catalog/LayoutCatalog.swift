//
//  LayoutCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Layout pane, in the order the pane shows them.
    enum LayoutPane {
        /// The group of the rows outside a titled group: the top row.
        static let pane = String(localized: "Layout")
        static let menuBar = String(localized: "Menu Bar")
        static let changes = String(localized: "Changes")
        static let notices = String(localized: "Notices")
        static let suggestions = String(localized: "Suggestions")
        static let search = String(localized: "Search")
        static let pictures = String(localized: "Pictures of the items")

        static let entries: [SettingsEntry] = {
            var entries: [SettingsEntry] = [
                .layoutView,
                .layoutFilter,
                .layoutTidyUp,
                .layoutUndo,
                .layoutAlwaysHidden,
                .layoutNewItems,
                .layoutApplyImmediately,
            ]
            // The row exists only where the macOS 27 backend runs, so the search never offers
            // one this Mac does not show.
            if MenuBarBackendKind.current == .accessibility27 {
                entries.append(.layoutCommandDragSetsSection)
            }
            entries += [
                .layoutSuggestRarelyUsed,
                .layoutStoredUsage,
                .layoutSmartCategories,
                .layoutSearchOpens,
                .layoutPictures,
            ]
            return entries
        }()
    }
}

extension SettingsEntry {
    static let layoutTidyUp = SettingsEntry(
        id: "layoutTidyUp",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.pane,
        label: String(localized: "Tidy Up"),
        info: String(localized: "Let holzBar propose which items to hide, from what it knows of the apps. You decide, and you can undo it.")
    )

    static let layoutView = SettingsEntry(
        id: "layoutView",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.pane,
        label: String(localized: "Bars or list"),
        info: String(localized: "Bars show the sections as the menu bar does. List shows every item with its app and a pop-up for its section, which also works with the keyboard and VoiceOver.")
    )

    static let layoutFilter = SettingsEntry(
        id: "layoutFilter",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.pane,
        label: String(localized: "Filter items"),
        info: String(localized: "Shows only the items whose name or app contains the text. In the bars, the others are dimmed.")
    )

    static let layoutUndo = SettingsEntry(
        id: "layoutUndo",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.pane,
        label: String(localized: "Undo the last change"),
        info: String(localized: "Takes back the last change of the layout, made here or in the menu bar. ⌘Z does the same while this window is in front.")
    )

    static let layoutAlwaysHidden = SettingsEntry(
        id: "layoutAlwaysHidden",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.menuBar,
        label: String(localized: "Always Hidden"),
        info: String(localized: "A third section for items that stay hidden when you show the hidden ones. ⌥-click on the holzBar icon shows them.")
    )

    static let layoutNewItems = SettingsEntry(
        id: "layoutNewItems",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.menuBar,
        label: String(localized: "New items go to"),
        info: String(localized: "Items holzBar has not seen before go to this section, and the New items tile shows where. Items that are already arranged stay where they are.")
    )

    static let layoutApplyImmediately = SettingsEntry(
        id: "layoutApplyImmediately",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.changes,
        label: String(localized: "Apply changes immediately"),
        info: String(localized: "Off: dragging an item only changes the drawing here, and the menu bar follows when you choose Apply. On: every move happens at once.")
    )

    static let layoutCommandDragSetsSection = SettingsEntry(
        id: "layoutCommandDragSetsSection",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.changes,
        label: String(localized: "Set the section with ⌘ Command-drag"),
        info: String(localized: "Hold ⌘ Command and drag an item in the menu bar across the holzBar icon: to the left of it, its app is hidden; to the right of it, visible. Off: the drag only reorders the bar.")
    )

    static let layoutSuggestRarelyUsed = SettingsEntry(
        id: "layoutSuggestRarelyUsed",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.suggestions,
        label: String(localized: "Suggest rarely used items"),
        info: String(localized: "Counts how often you open each item, per day for 30 days. The counts stay on this Mac, are not exported or backed up, and are deleted when you turn this off.")
    )

    static let layoutStoredUsage = SettingsEntry(
        id: "layoutStoredUsage",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.suggestions,
        label: String(localized: "Stored usage"),
        info: String(localized: "Opens per day, oldest first. This is everything holzBar keeps.")
    )

    static let layoutSmartCategories = SettingsEntry(
        id: "layoutSmartCategories",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.search,
        label: String(localized: "Smart Categories"),
        info: String(localized: "Adds category buttons to the search, such as Network and Media, worked out from what holzBar can read about each app. Nothing is recorded.")
    )

    static let layoutSearchOpens = SettingsEntry(
        id: "layoutSearchOpens",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.search,
        label: String(localized: "Items you open come first"),
        info: String(localized: "The search remembers how often and how lately you open an item from it, so what you use most comes first. The counts stay on this Mac, are not exported or backed up, and Forget deletes them.")
    )

    static let layoutPictures = SettingsEntry(
        id: "layoutPictures",
        pane: .layout,
        group: SettingsCatalog.LayoutPane.pictures,
        label: String(localized: "Pictures instead of app icons"),
        info: String(localized: "macOS lets an app take pictures of your menu bar only with Screen Recording. If macOS then offers to quit and reopen holzBar, choose Quit & Reopen.")
    )
}
