//
//  GeneralCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the General pane, in the order the pane shows them. The dot
    /// switch is an entry only on macOS 27, where it exists.
    enum GeneralPane {
        static let startup = String(localized: "Startup")
        static let icon = String(localized: "Icon in the menu bar")

        static let entries: [SettingsEntry] = {
            var entries: [SettingsEntry] = [
                .generalLaunchAtLogin,
                .generalAllowLoginItem,
                .generalShowWhatsNew,
                .generalIcon,
                .generalCustomImage,
                .generalCustomIconTemplate,
                .generalHiddenCount,
            ]
            if #available(macOS 27.0, *) {
                entries.append(.generalCaptureDot)
            }
            return entries
        }()
    }
}

extension SettingsEntry {
    static let generalLaunchAtLogin = SettingsEntry(
        id: "generalLaunchAtLogin",
        pane: .general,
        group: SettingsCatalog.GeneralPane.startup,
        label: String(localized: "Launch at login")
    )

    static let generalAllowLoginItem = SettingsEntry(
        id: "generalAllowLoginItem",
        pane: .general,
        group: SettingsCatalog.GeneralPane.startup,
        label: String(localized: "Allow login item"),
        info: String(localized: "Allow holzBar in System Settings to launch it at login.")
    )

    static let generalShowWhatsNew = SettingsEntry(
        id: "generalShowWhatsNew",
        pane: .general,
        group: SettingsCatalog.GeneralPane.startup,
        label: String(localized: "Show What's New after an update"),
        info: String(localized: "The What's New window opens once after holzBar is updated.")
    )

    static let generalIcon = SettingsEntry(
        id: "generalIcon",
        pane: .general,
        group: SettingsCatalog.GeneralPane.icon,
        label: String(localized: "Icon"),
        info: String(localized: "The holzBar icon in the menu bar. “Custom” appears once you have chosen an image.")
    )

    static let generalCustomImage = SettingsEntry(
        id: "generalCustomImage",
        pane: .general,
        group: SettingsCatalog.GeneralPane.icon,
        label: String(localized: "Custom image")
    )

    static let generalCustomIconTemplate = SettingsEntry(
        id: "generalCustomIconTemplate",
        pane: .general,
        group: SettingsCatalog.GeneralPane.icon,
        label: String(localized: "Custom icon adapts to the menu bar"),
        info: String(localized: "Shows the image in one color that matches a light or dark menu bar. This removes every color from the image.")
    )

    static let generalHiddenCount = SettingsEntry(
        id: "generalHiddenCount",
        pane: .general,
        group: SettingsCatalog.GeneralPane.icon,
        label: String(localized: "Show the number of hidden items"),
        info: String(localized: "A small number on the holzBar icon says how many items are hidden right now.")
    )

    static let generalCaptureDot = SettingsEntry(
        id: "generalCaptureDot",
        pane: .general,
        group: SettingsCatalog.GeneralPane.icon,
        label: String(localized: "Dot on the holzBar icon for microphone or camera"),
        info: String(localized: "Orange for the microphone, green for the camera. Uses no permission; holzBar cannot tell when an app records the screen. The small green dot beside the clock still appears.")
    )
}
