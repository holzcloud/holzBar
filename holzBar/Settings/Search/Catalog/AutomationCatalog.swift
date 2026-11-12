//
//  AutomationCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Automation pane, in the order the pane shows them. Rules are
    /// user data (names, conditions, Wi-Fi and app names): none of them enters the index.
    enum AutomationPane {
        static let rules = String(localized: "Rules")
        static let scripts = String(localized: "Scripts")
        static let profileHooks = String(localized: "Profile hooks")
        static let storage = String(localized: "Storage")

        static let entries: [SettingsEntry] = [
            .automationAddRule,
            .automationScriptsFolder,
            .automationChooseScriptsFolder,
            .automationOpenScriptsFolder,
            .automationCheckScripts,
            .automationAddHook,
            .automationStorageRules,
            .automationStorageScripts,
        ]
    }
}

extension SettingsEntry {
    static let automationAddRule = SettingsEntry(
        id: "automationAddRule",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.rules,
        label: String(localized: "Add rule…"),
        info: String(localized: "A rule changes the menu bar when something happens. A new rule is off and starts with the condition “On battery”. At most 50 rules.")
    )

    static let automationScriptsFolder = SettingsEntry(
        id: "automationScriptsFolder",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.scripts,
        label: String(localized: "Folder"),
        info: String(localized: "Scripts run as you, with holzBar's permissions. Only scripts in this folder run, and only after you allowed their exact content.")
    )

    static let automationChooseScriptsFolder = SettingsEntry(
        id: "automationChooseScriptsFolder",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.scripts,
        label: String(localized: "Choose Folder…"),
        info: String(localized: "With a new folder, every approval is removed. Each script in it needs your approval again.")
    )

    static let automationOpenScriptsFolder = SettingsEntry(
        id: "automationOpenScriptsFolder",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.scripts,
        label: String(localized: "Open Scripts Folder")
    )

    static let automationCheckScripts = SettingsEntry(
        id: "automationCheckScripts",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.scripts,
        label: String(localized: "Scripts of the rules"),
        info: String(localized: "Reads the scripts folder again and checks every rule now, without waiting for the next change.")
    )

    static let automationAddHook = SettingsEntry(
        id: "automationAddHook",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.profileHooks,
        label: String(localized: "Add hook"),
        info: String(localized: "Runs an allowed script before or after a layout profile is applied. A profile applied by a URL, a Shortcut or a Focus runs no hooks. At most 50.")
    )

    static let automationStorageRules = SettingsEntry(
        id: "automationStorageRules",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.storage,
        label: String(localized: "Rules")
    )

    static let automationStorageScripts = SettingsEntry(
        id: "automationStorageScripts",
        pane: .automation,
        group: SettingsCatalog.AutomationPane.storage,
        label: String(localized: "Scripts, approvals and hooks"),
        info: String(localized: "They are in the file Scripts.json in ~/Library/Application Support/holzBar and are never exported.")
    )
}
