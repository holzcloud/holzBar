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

        static let entries: [SettingsEntry] = [
            .automationAddRule,
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
}
