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
}
