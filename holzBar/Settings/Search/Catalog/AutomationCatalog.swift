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

        static let entries: [SettingsEntry] = [
            .automationAddRule,
            .automationScriptsFolder,
            .automationChooseScriptsFolder,
            .automationOpenScriptsFolder,
            .automationCheckScripts,
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
}
