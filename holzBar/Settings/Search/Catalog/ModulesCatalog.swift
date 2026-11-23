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
        static let monitor = String(localized: "System monitor")

        /// The group of an area. A module of another area needs its group here and in the pane;
        /// the test of the module catalog fails until it has one.
        static func group(of area: ModuleArea) -> String {
            switch area {
            case .menuBar: menuBar
            case .notch: notch
            case .monitor: monitor
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
            .modulesNotchHubShowsActiveFirst,
            .modulesNotchHubOpensOnHover,
            .modulesNotchHubGestures,
            .modulesNotchHubDisplays,
            .modulesNotchHubCutout,
            .modulesNotchHubBounces,
            // Settings of the hub modules, in catalog order.
            .modulesTimersFinishSound,
            .modulesCalendarShowsAllDay,
            .modulesCalendarCalendars,
            .modulesCalendarCountdown,
            .modulesLiveActivitiesCapture,
            .modulesLiveActivitiesDownloads,
            .modulesFileDropOpensOnDrag,
            .modulesFileDropRemovesAfterDrop,
            .modulesDisplayControlsBrightness,
            .modulesDisplayControlsExternalMonitors,
            .modulesAccessoryAlertsDevices,
            .modulesAccessoryAlertsConnect,
            .modulesAccessoryAlertsDisconnect,
            .modulesAccessoryAlertsReadsBattery,
            .modulesAccessoryAlertsLowBattery,
            .modulesAccessoryAlertsLowBatteryLevel,
            .modulesIndicatorsInputSource,
            .modulesIndicatorsInputSourceDuration,
            .modulesIndicatorsVolumeBrightness,
            .modulesNotificationsExcludedApps,
            .modulesNotificationsDisplayTime,
            .modulesNowPlayingAppleMusic,
            .modulesNowPlayingSpotify,
            .modulesNowPlayingReadsAllApps,
            // Settings of the System monitor modules, in the order of the pane.
            .modulesReadoutsReadsGPU,
            .modulesReadoutsTileCPU,
            .modulesReadoutsThermalState,
            .modulesReadoutsTileGPU,
            .modulesReadoutsTileMemory,
            .modulesReadoutsTileNetwork,
            .modulesReadoutsTileDisk,
            .modulesReadoutsTileBattery,
            .modulesReadoutsTileRefresh,
            .modulesReadoutsRateUnit,
            // Settings of System alerts, in the order of the contract.
            .modulesSystemAlertsNotifications,
            .modulesSystemAlertsCPU,
            .modulesSystemAlertsCPUThreshold,
            .modulesSystemAlertsCPUDuration,
            .modulesSystemAlertsMemoryPressure,
            .modulesSystemAlertsMemoryPressureThreshold,
            .modulesSystemAlertsMemoryPressureDuration,
            .modulesSystemAlertsThermal,
            .modulesSystemAlertsThermalThreshold,
            .modulesSystemAlertsThermalDuration,
            .modulesSystemAlertsFreeDisk,
            .modulesSystemAlertsFreeDiskThreshold,
            .modulesSystemAlertsFreeDiskDuration,
            .modulesSystemAlertsMacBattery,
            .modulesSystemAlertsMacBatteryThreshold,
            .modulesSystemAlertsMacBatteryDuration,
            .modulesSystemAlertsTest,
        ]

        /// The Mac battery rule's entries: a Mac without an internal battery has no such rule.
        private static let macBatteryEntryIDs: Set<String> = [
            SettingsEntry.modulesSystemAlertsMacBattery.id,
            SettingsEntry.modulesSystemAlertsMacBatteryThreshold.id,
            SettingsEntry.modulesSystemAlertsMacBatteryDuration.id,
        ]

        /// Whether a row entry belongs to a module this Mac can run.
        static func isAvailable(_ entry: SettingsEntry) -> Bool {
            if entry.id == SettingsEntry.modulesClockOpensNotificationCenter.id {
                if #available(macOS 27.0, *) {
                    return true
                }
                return false
            }
            if macBatteryEntryIDs.contains(entry.id) {
                return SystemAlertsSettings.hasInternalBattery
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

    static let modulesNotchHubShowsActiveFirst = SettingsEntry(
        id: "modulesNotchHubShowsActiveFirst",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Show what is active first"),
        info: String(localized: "When the hub opens, a meeting within 15 minutes, a live activity or playing music comes first. When off, it opens on the module you chose last."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubOpensOnHover = SettingsEntry(
        id: "modulesNotchHubOpensOnHover",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Open on hover"),
        info: String(localized: "The pointer has to rest at the notch, or at the top center on a display without one."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubGestures = SettingsEntry(
        id: "modulesNotchHubGestures",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Gestures"),
        info: String(localized: "Scroll down on the notch to open the hub and up to close it. Swipe sideways to skip a track."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubDisplays = SettingsEntry(
        id: "modulesNotchHubDisplays",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Show the hub on"),
        info: String(localized: "Follow the pointer opens the hub only on the display where the pointer is."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubCutout = SettingsEntry(
        id: "modulesNotchHubCutout",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Display cutout"),
        info: String(localized: "Where the hub opens around the camera. Automatic tells a notch from Apple's Dynamic Island; choose one if it is wrong. With the Dynamic Island the hub opens below it."),
        module: NotchHubController.moduleID
    )

    static let modulesNotchHubBounces = SettingsEntry(
        id: "modulesNotchHubBounces",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Bounce"),
        info: String(localized: "Off opens and closes the hub with a plain ease and no overshoot."),
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

    static let modulesCalendarCountdown = SettingsEntry(
        id: "modulesCalendarCountdown",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Countdown before a meeting"),
        info: String(localized: "Counts down in the closed notch before a meeting starts. It never shows the event's title."),
        module: "calendar"
    )

    static let modulesLiveActivitiesCapture = SettingsEntry(
        id: "modulesLiveActivitiesCapture",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Camera and microphone in use"),
        info: String(localized: "The notch widens while another app uses the camera or the microphone. holzBar reads no audio or video."),
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

    static let modulesDisplayControlsExternalMonitors = SettingsEntry(
        id: "modulesDisplayControlsExternalMonitors",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "External monitors (DDC)"),
        info: String(localized: "Sets brightness, contrast, volume and mute of external monitors that support DDC. Uses a private macOS interface. It switches itself off if macOS changes it."),
        module: "display-controls"
    )

    static let modulesAccessoryAlertsDevices = SettingsEntry(
        id: "modulesAccessoryAlertsDevices",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Devices"),
        info: String(localized: "Levels need Read battery levels below. Names stay on this Mac."),
        module: "accessory-alerts"
    )

    static let modulesAccessoryAlertsConnect = SettingsEntry(
        id: "modulesAccessoryAlertsConnect",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Alert when an accessory connects"),
        info: String(localized: "The notch widens for five seconds and shows the accessory's symbol."),
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

    static let modulesIndicatorsInputSource = SettingsEntry(
        id: "modulesIndicatorsInputSource",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Input source"),
        info: String(localized: "Flashes the keyboard layout in the notch when you switch it. It needs two or more input sources."),
        module: IndicatorLook.moduleID
    )

    static let modulesIndicatorsInputSourceDuration = SettingsEntry(
        id: "modulesIndicatorsInputSourceDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Show for"),
        info: String(localized: "How long the input source stays in the notch."),
        module: IndicatorLook.moduleID
    )

    static let modulesIndicatorsVolumeBrightness = SettingsEntry(
        id: "modulesIndicatorsVolumeBrightness",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Volume and brightness"),
        info: String(localized: "Shows the volume in the notch when it changes. macOS still shows its own display unless you replace it below."),
        module: IndicatorLook.moduleID
    )

    static let modulesNotificationsExcludedApps = SettingsEntry(
        id: "modulesNotificationsExcludedApps",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Excluded apps"),
        info: String(localized: "Hide an app with the crossed-out eye on one of its notifications."),
        module: "notifications"
    )

    static let modulesNotificationsDisplayTime = SettingsEntry(
        id: "modulesNotificationsDisplayTime",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.notch,
        label: String(localized: "Display time"),
        info: String(localized: "How long a new notification shows as a count in the closed notch."),
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

    // MARK: Settings of the System monitor modules

    static let modulesReadoutsReadsGPU = SettingsEntry(
        id: "modulesReadoutsReadsGPU",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Read GPU load"),
        info: String(
            localized: "Reads how busy the graphics processor is, for its tile and widget. Uses a private macOS interface. It switches itself off if macOS changes it."
        ),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileGPU = SettingsEntry(
        id: "modulesReadoutsTileGPU",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "GPU tile"),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileCPU = SettingsEntry(
        id: "modulesReadoutsTileCPU",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "CPU tile"),
        info: String(localized: "Total load, and the load of each core cluster when the chip reports them."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsThermalState = SettingsEntry(
        id: "modulesReadoutsThermalState",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Thermal state"),
        info: String(localized: "Shows on the CPU tile when the Mac runs warm: Fair, Serious or Critical."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileMemory = SettingsEntry(
        id: "modulesReadoutsTileMemory",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Memory tile"),
        info: String(localized: "Memory in use. The ring turns amber or red with memory pressure, and swap shows when it is used."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileNetwork = SettingsEntry(
        id: "modulesReadoutsTileNetwork",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Network tile"),
        info: String(localized: "Download speed, with the upload speed below it. Counts Wi-Fi and Ethernet, not VPN tunnels."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileDisk = SettingsEntry(
        id: "modulesReadoutsTileDisk",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Disk tile"),
        info: String(localized: "Free space on the startup disk; the ring shows how much is used."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileBattery = SettingsEntry(
        id: "modulesReadoutsTileBattery",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Battery tile"),
        info: String(localized: "Charge, time left and charging state. The charge respects the charge limit."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsTileRefresh = SettingsEntry(
        id: "modulesReadoutsTileRefresh",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Refresh tiles every"),
        info: String(localized: "Tiles read only while the hub is open. Free disk space is read about once a minute."),
        module: ReadoutsSettings.moduleID
    )

    static let modulesReadoutsRateUnit = SettingsEntry(
        id: "modulesReadoutsRateUnit",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Network speed unit"),
        info: String(localized: "Used by the Network tile and the Network Speed widget."),
        module: ReadoutsSettings.moduleID
    )

    // MARK: Settings of System alerts

    static let modulesSystemAlertsNotifications = SettingsEntry(
        id: "modulesSystemAlertsNotifications",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "System notifications"),
        info: String(localized: "Also sends each alert to Notification Center, one per rule. macOS asks for permission when you switch this on."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsCPU = SettingsEntry(
        id: "modulesSystemAlertsCPU",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "CPU load"),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsCPUThreshold = SettingsEntry(
        id: "modulesSystemAlertsCPUThreshold",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Alert above"),
        info: String(localized: "Alerts when CPU load stays above this."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsCPUDuration = SettingsEntry(
        id: "modulesSystemAlertsCPUDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Held for"),
        info: String(localized: "The condition must last this long before an alert shows."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMemoryPressure = SettingsEntry(
        id: "modulesSystemAlertsMemoryPressure",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Memory pressure"),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMemoryPressureThreshold = SettingsEntry(
        id: "modulesSystemAlertsMemoryPressureThreshold",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Alert at"),
        info: String(localized: "Alerts when memory pressure reaches this level."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMemoryPressureDuration = SettingsEntry(
        id: "modulesSystemAlertsMemoryPressureDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Held for"),
        info: String(localized: "The condition must last this long before an alert shows."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsThermal = SettingsEntry(
        id: "modulesSystemAlertsThermal",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Thermal state"),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsThermalThreshold = SettingsEntry(
        id: "modulesSystemAlertsThermalThreshold",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Alert at"),
        info: String(localized: "Alerts when the thermal state reaches this level."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsThermalDuration = SettingsEntry(
        id: "modulesSystemAlertsThermalDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Held for"),
        info: String(localized: "The condition must last this long before an alert shows."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsFreeDisk = SettingsEntry(
        id: "modulesSystemAlertsFreeDisk",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Free disk space"),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsFreeDiskThreshold = SettingsEntry(
        id: "modulesSystemAlertsFreeDiskThreshold",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Alert below"),
        info: String(localized: "Alerts when free disk space falls below this."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsFreeDiskDuration = SettingsEntry(
        id: "modulesSystemAlertsFreeDiskDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Held for"),
        info: String(localized: "The condition must last this long before an alert shows."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMacBattery = SettingsEntry(
        id: "modulesSystemAlertsMacBattery",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Mac battery"),
        info: String(localized: "Alerts only while the Mac runs on battery power; plugging in clears it. The charge limit is respected."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMacBatteryThreshold = SettingsEntry(
        id: "modulesSystemAlertsMacBatteryThreshold",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Alert below"),
        info: String(localized: "Alerts when the battery falls below this."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsMacBatteryDuration = SettingsEntry(
        id: "modulesSystemAlertsMacBatteryDuration",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Held for"),
        info: String(localized: "The condition must last this long before an alert shows."),
        module: SystemAlertsSettings.moduleID
    )

    static let modulesSystemAlertsTest = SettingsEntry(
        id: "modulesSystemAlertsTest",
        pane: .modules,
        group: SettingsCatalog.ModulesPane.monitor,
        label: String(localized: "Test alert"),
        info: String(localized: "Shows a sample alert in the notch, and as a notification when those are on."),
        module: SystemAlertsSettings.moduleID
    )
}
