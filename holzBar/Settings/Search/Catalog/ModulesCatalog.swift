//
//  ModulesCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Modules pane, in the order the pane shows them: one entry
    /// per module this Mac can run, then the fixed rows inside and beside the modules' open areas.
    enum ModulesPane {
        static let menuBar = String(localized: "Menu Bar")
        static let notch = String(localized: "Notch")

        /// The group of an area. A module of another area needs its group here and in the pane;
        /// the test of the module catalog fails until it has one.
        static func group(of area: ModuleArea) -> String {
            switch area {
            case .menuBar: menuBar
            case .notch: notch
            default: area.rawValue
            }
        }

        /// Whether this Mac can run the module: Drag in the Menu Bar and Apple Items are left out
        /// where they are unsupported. The pane and the search list the same modules.
        static func isSupported(_ module: ModuleDescriptor) -> Bool {
            switch module.id {
            case MenuBarDragController.moduleID: MenuBarDragController.isSupported
            case AppleItems.moduleID: AppleItems.isSupported
            default: true
            }
        }

        /// The entry of a module's row: its title, and its summary as the info.
        static func moduleEntry(for module: ModuleDescriptor) -> SettingsEntry {
            let summary = Bundle.main.localizedString(forKey: module.summaryKey, value: nil, table: nil)
            return SettingsEntry(
                id: "modules.\(module.id)",
                pane: .modules,
                group: group(of: module.area),
                label: Bundle.main.localizedString(forKey: module.titleKey, value: nil, table: nil),
                info: summary,
                summary: summary,
                module: module.id
            )
        }

        /// The fixed rows inside the module rows' open areas and beside them. The plans of the
        /// module settings append their entries here.
        static let rowEntries: [SettingsEntry] = [
            .modulesWidgetsAdd,
            .modulesClockOpensNotificationCenter,
            .modulesAppleItemsHideClock,
            .modulesAppleItemsHideControlCenter,
            .modulesAppleItemsHideWiFi,
            .modulesAppleItemsHideBattery,
            .modulesAppleItemsReplacements,
            .modulesNotchHubOpensOnHover,
            .modulesNotchHubDisplays,
            // Settings of the hub modules, in catalog order.
            .modulesTimersFinishSound,
            .modulesCalendarShowsAllDay,
            .modulesCalendarCalendars,
            .modulesLiveActivitiesCapture,
            .modulesLiveActivitiesDownloads,
            .modulesFileDropOpensOnDrag,
            .modulesFileDropRemovesAfterDrop,
            .modulesDisplayControlsBrightness,
            .modulesAccessoryAlertsConnect,
            .modulesAccessoryAlertsDisconnect,
            .modulesAccessoryAlertsReadsBattery,
            .modulesAccessoryAlertsLowBattery,
            .modulesAccessoryAlertsLowBatteryLevel,
            .modulesNotificationsExcludedApps,
            .modulesNowPlayingAppleMusic,
            .modulesNowPlayingSpotify,
            .modulesNowPlayingReadsAllApps,
        ]

        /// Whether a row entry belongs to a module this Mac can run.
        static func isAvailable(_ entry: SettingsEntry) -> Bool {
            if entry.id == SettingsEntry.modulesClockOpensNotificationCenter.id {
                if #available(macOS 27.0, *) {
                    return true
                }
                return false
            }
            guard
                let moduleID = entry.module,
                let module = ModuleCatalog.all.first(where: { $0.id == moduleID })
            else {
                return true
            }
            return isSupported(module)
        }

        static let entries: [SettingsEntry] =
            ModuleCatalog.all.filter { isSupported($0) }.map { moduleEntry(for: $0) }
            + rowEntries.filter { isAvailable($0) }
    }
}

extension SettingsEntry {
    static let modulesWidgetsAdd = SettingsEntry(
        id: "modulesWidgetsAdd",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Add Widget…"),
        info: String(localized: "Text readouts, a Shortcut button, a script and ready-made items: Focus, AirDrop, Media Controls, Fast User Switching, Timer, App Launcher."),
        module: MenuBarWidgets.moduleID
    )

    static let modulesClockOpensNotificationCenter = SettingsEntry(
        id: "modulesClockOpensNotificationCenter",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Open Notification Center from the clock"),
        info: String(localized: "While items are hidden, macOS 27 ignores a click on the clock, so holzBar lifts the hiding for a moment and clicks again. When off, the clock does nothing then.")
    )

    static let modulesAppleItemsHideClock = SettingsEntry(
        id: "modulesAppleItemsHideClock",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Hide the clock"),
        module: AppleItems.moduleID
    )

    static let modulesAppleItemsHideControlCenter = SettingsEntry(
        id: "modulesAppleItemsHideControlCenter",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Hide Control Center"),
        module: AppleItems.moduleID
    )

    static let modulesAppleItemsHideWiFi = SettingsEntry(
        id: "modulesAppleItemsHideWiFi",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Hide Wi-Fi"),
        module: AppleItems.moduleID
    )

    static let modulesAppleItemsHideBattery = SettingsEntry(
        id: "modulesAppleItemsHideBattery",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Hide the battery"),
        info: String(localized: "While a system item is hidden, Control Center does not show its camera and microphone indicator; holzBar marks its own icon instead."),
        module: AppleItems.moduleID
    )

    static let modulesAppleItemsReplacements = SettingsEntry(
        id: "modulesAppleItemsReplacements",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.menuBar,
        label: String(localized: "Replacement items"),
        info: String(localized: "Hide an Apple app's items in Layout, and keep the ones you want one click away here. At most six."),
        module: AppleItems.moduleID
    )

    static let modulesNotchHubOpensOnHover = SettingsEntry(
        id: "modulesNotchHubOpensOnHover",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Open on hover"),
        info: String(localized: "The pointer has to rest at the notch, or at the top center on a display without one."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubDisplays = SettingsEntry(
        id: "modulesNotchHubDisplays",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Show the hub on"),
        module: NotchHubController.moduleID
    )

    // MARK: Settings of the hub modules

    static let modulesTimersFinishSound = SettingsEntry(
        id: "modulesTimersFinishSound",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Finish sound"),
        info: String(localized: "Applies to the timers in the hub. The Timer widget in the menu bar always plays Glass."),
        module: "timers"
    )

    static let modulesCalendarShowsAllDay = SettingsEntry(
        id: "modulesCalendarShowsAllDay",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Show all-day events"),
        module: "calendar"
    )

    static let modulesCalendarCalendars = SettingsEntry(
        id: "modulesCalendarCalendars",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Calendars"),
        info: String(localized: "A calendar you switch off is hidden only in the hub."),
        module: "calendar"
    )

    static let modulesLiveActivitiesCapture = SettingsEntry(
        id: "modulesLiveActivitiesCapture",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Camera and microphone in use"),
        info: String(localized: "A capsule shows while another app uses the camera or the microphone. holzBar reads no audio or video."),
        module: "live-activities"
    )

    static let modulesLiveActivitiesDownloads = SettingsEntry(
        id: "modulesLiveActivitiesDownloads",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Downloads"),
        info: String(localized: "Asks for access to your Downloads folder when you switch it on. holzBar never reads what you download."),
        module: "live-activities"
    )

    static let modulesFileDropOpensOnDrag = SettingsEntry(
        id: "modulesFileDropOpensOnDrag",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Open when you drag a file to the notch"),
        info: String(localized: "The pointer has to rest at the notch while you drag."),
        module: "file-drop"
    )

    static let modulesFileDropRemovesAfterDrop = SettingsEntry(
        id: "modulesFileDropRemovesAfterDrop",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Remove a file from the stash after you dropped it"),
        info: String(localized: "When off, a file stays in the stash until you remove it."),
        module: "file-drop"
    )

    static let modulesDisplayControlsBrightness = SettingsEntry(
        id: "modulesDisplayControlsBrightness",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Brightness"),
        info: String(localized: "Uses a private macOS interface. It switches itself off if macOS changes it."),
        module: "display-controls"
    )

    static let modulesAccessoryAlertsConnect = SettingsEntry(
        id: "modulesAccessoryAlertsConnect",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Alert when an accessory connects"),
        info: String(localized: "A capsule below the notch names the accessory for five seconds."),
        module: "accessory-alerts"
    )

    static let modulesAccessoryAlertsDisconnect = SettingsEntry(
        id: "modulesAccessoryAlertsDisconnect",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Alert when an accessory disconnects"),
        info: String(localized: "AirPods disconnect whenever they go back in their case."),
        module: "accessory-alerts"
    )

    static let modulesAccessoryAlertsReadsBattery = SettingsEntry(
        id: "modulesAccessoryAlertsReadsBattery",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Read battery levels"),
        info: String(localized: "Levels are read on this Mac and sent nowhere. Uses a private macOS interface. It switches itself off if macOS changes it."),
        module: "accessory-alerts"
    )

    static let modulesAccessoryAlertsLowBattery = SettingsEntry(
        id: "modulesAccessoryAlertsLowBattery",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Alert when the battery is low"),
        module: "accessory-alerts"
    )

    static let modulesAccessoryAlertsLowBatteryLevel = SettingsEntry(
        id: "modulesAccessoryAlertsLowBatteryLevel",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Low battery level"),
        module: "accessory-alerts"
    )

    static let modulesNotificationsExcludedApps = SettingsEntry(
        id: "modulesNotificationsExcludedApps",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Excluded apps"),
        info: String(localized: "Hide an app with the crossed-out eye on one of its notifications."),
        module: "notifications"
    )

    static let modulesNowPlayingAppleMusic = SettingsEntry(
        id: "modulesNowPlayingAppleMusic",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Apple Music"),
        module: "now-playing"
    )

    static let modulesNowPlayingSpotify = SettingsEntry(
        id: "modulesNowPlayingSpotify",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Spotify"),
        info: String(localized: "Apple Music and Spotify tell holzBar what they play. One of the two always stays on."),
        module: "now-playing"
    )

    static let modulesNowPlayingReadsAllApps = SettingsEntry(
        id: "modulesNowPlayingReadsAllApps",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Read all apps"),
        info: String(localized: "Shows what browsers and video apps play, too, through a helper that runs only while the hub is open. Uses a private macOS interface. It switches itself off if macOS changes it."),
        module: "now-playing"
    )
}
