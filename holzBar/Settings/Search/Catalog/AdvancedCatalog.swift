//
//  AdvancedCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Advanced pane, in the order the pane shows them. Rows that
    /// exist only before macOS 27 are entries only there.
    enum AdvancedPane {
        static let menuBar = String(localized: "Menu bar")
        static let appMenus = String(localized: "App menus")
        static let itemSpacing = String(localized: "Item spacing")
        static let backUp = String(localized: "Back up settings")
        static let permissions = String(localized: "Permissions")

        static let entries: [SettingsEntry] = {
            var isBeforeMacOS27 = true
            if #available(macOS 27.0, *) {
                isBeforeMacOS27 = false
            }
            var entries = [SettingsEntry]()
            if isBeforeMacOS27 {
                entries += [.advancedDividerStyle, .advancedShowAllSectionsOnDrag]
            }
            entries.append(.advancedSecondaryContextMenu)
            if isBeforeMacOS27 {
                entries += [
                    .advancedKeepLiveActivities,
                    .advancedSystemItemsInPlace,
                    .advancedHideAppMenus,
                    .advancedKeepDockIconHidden,
                ]
            }
            entries += [
                .advancedItemSpacing,
                .advancedApplySpacing,
                .advancedDefaultSpacing,
                .advancedExportSettings,
                .advancedImportSettings,
                .advancedPermissionAccessibility,
                .advancedPermissionScreenRecording,
                .advancedPermissionCalendar,
                .advancedPermissionBluetooth,
            ]
            return entries
        }()
    }
}

extension SettingsEntry {
    static let advancedDividerStyle = SettingsEntry(
        id: "advancedDividerStyle",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.menuBar,
        label: String(localized: "Divider between the sections")
    )

    static let advancedShowAllSectionsOnDrag = SettingsEntry(
        id: "advancedShowAllSectionsOnDrag",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.menuBar,
        label: String(localized: "Show all sections while ⌘ Command-dragging"),
        info: String(localized: "While you ⌘ Command-drag an item in the menu bar, holzBar shows every section.")
    )

    static let advancedSecondaryContextMenu = SettingsEntry(
        id: "advancedSecondaryContextMenu",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.menuBar,
        label: String(localized: "Right-click on empty menu bar opens holzBar's menu"),
        info: String(localized: "Right-click in an empty area of the menu bar to display a minimal version of holzBar's menu. Disable this setting if you encounter conflicts with other apps.")
    )

    static let advancedKeepLiveActivities = SettingsEntry(
        id: "advancedKeepLiveActivities",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.menuBar,
        label: String(localized: "Keep Apple's Live Activities visible"),
        info: String(localized: "Live Activities from your iPhone stay in the menu bar instead of being hidden.")
    )

    static let advancedSystemItemsInPlace = SettingsEntry(
        id: "advancedSystemItemsInPlace",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.menuBar,
        label: String(localized: "Leave system items in place"),
        info: String(localized: "Clock, battery, Wi-Fi, Control Center and sound: profiles, restored layouts and rules leave them where they are. You can still move them yourself.")
    )

    static let advancedHideAppMenus = SettingsEntry(
        id: "advancedHideAppMenus",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.appMenus,
        label: String(localized: "Hide app menus when showing"),
        info: String(localized: "Make more room in the menu bar by hiding the current app menus if needed. macOS requires holzBar to make itself visible in the Dock while this setting is in effect.")
    )

    static let advancedKeepDockIconHidden = SettingsEntry(
        id: "advancedKeepDockIconHidden",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.appMenus,
        label: String(localized: "Keep the Dock icon hidden"),
        info: String(localized: "macOS hides another app's menus only while holzBar is in the Dock. With this on, holzBar never shows a Dock icon, and the menus stay.")
    )

    static let advancedExportSettings = SettingsEntry(
        id: "advancedExportSettings",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.backUp,
        label: String(localized: "Export settings"),
        info: String(localized: "Exports layout, hotkeys and appearance to a file that can be imported on another Mac.")
    )

    static let advancedImportSettings = SettingsEntry(
        id: "advancedImportSettings",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.backUp,
        label: String(localized: "Import settings")
    )

    static let advancedPermissionAccessibility = SettingsEntry(
        id: "advancedPermissionAccessibility",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.permissions,
        label: String(localized: "Accessibility"),
        info: String(localized: "holzBar uses it to find, move, show and click menu bar items and to notice clicks, scrolls and hovers. The Notifications module needs it too.")
    )

    static let advancedPermissionScreenRecording = SettingsEntry(
        id: "advancedPermissionScreenRecording",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.permissions,
        label: String(localized: "Screen Recording"),
        info: String(localized: "Pictures of the menu bar items in the holzBar Shelf, the search and Layout, and the moving wallpaper before macOS 27. Without it, holzBar shows the apps' icons.")
    )

    static let advancedPermissionCalendar = SettingsEntry(
        id: "advancedPermissionCalendar",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.permissions,
        label: String(localized: "Calendar"),
        info: String(localized: "The Calendar module shows your next events and their meeting links in the notch hub.")
    )

    static let advancedPermissionBluetooth = SettingsEntry(
        id: "advancedPermissionBluetooth",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.permissions,
        label: String(localized: "Bluetooth"),
        info: String(localized: "Accessory alerts shows which paired accessories are connected, and automation rules can react to a Bluetooth device.")
    )

    static let advancedItemSpacing = SettingsEntry(
        id: "advancedItemSpacing",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.itemSpacing,
        label: String(localized: "Menu bar item spacing"),
        info: String(localized: "Apply relaunches every app with a menu bar item; some you may need to relaunch yourself. You may need to log out and back in.")
    )

    static let advancedApplySpacing = SettingsEntry(
        id: "advancedApplySpacing",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.itemSpacing,
        label: String(localized: "Apply spacing")
    )

    static let advancedDefaultSpacing = SettingsEntry(
        id: "advancedDefaultSpacing",
        pane: .advanced,
        group: SettingsCatalog.AdvancedPane.itemSpacing,
        label: String(localized: "Default spacing")
    )
}
