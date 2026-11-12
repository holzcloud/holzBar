//
//  AutomationSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The rules: "when this is true, do that". One settings group of module rows, one per rule; the
/// editor of a rule opens in its row's open area, one at a time. "Add rule…" sits directly under
/// the list. Then the groups Scripts, Profile hooks and Storage.
struct AutomationSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var manager: AutomationManager
    @State private var editingID: UUID?
    @State private var deletionID: UUID?
    /// The rule added last: its editor puts the keyboard focus into the Name field.
    @State private var focusedNewRuleID: UUID?

    private var profileNames: [String] {
        appState.profiles.profiles.map(\.name)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { deletionID != nil },
            set: { isPresented in
                if !isPresented {
                    deletionID = nil
                }
            }
        )
    }

    var body: some View {
        SettingsPaneHost(.automation) {
            rulesGroup
            ScriptsSection(store: manager.scriptStore, manager: manager)
            ProfileHooksSection(store: manager.scriptStore)
            storageGroup
        }
        .holzBarConfirmation(
            isPresented: isConfirmingDeletion,
            title: Text("Delete this rule?"),
            confirmTitle: "Delete",
            isDestructive: true
        ) {
            if let id = deletionID {
                if editingID == id {
                    editingID = nil
                }
                manager.removeRule(withID: id)
            }
            deletionID = nil
        }
    }

    /// Where rules, scripts, approvals and hooks live (D-55).
    private var storageGroup: some View {
        SettingsGroup(SettingsCatalog.AutomationPane.storage) {
            SettingsValueRow(
                .automationStorageRules,
                value: Text("Rules stay on this Mac. An exported settings file contains them, except rules that run a script.")
            )
            SettingsValueRow(.automationStorageScripts, value: Text("Only on this Mac"))
        }
    }

    private var rulesGroup: some View {
        SettingsGroup(
            SettingsCatalog.AutomationPane.rules,
            footnote: Text("With no rules, nothing is observed.")
        ) {
            if manager.rules.isEmpty {
                SettingsEmptyRow(systemImage: "bolt.badge.automatic", Text("No rules yet: a rule changes the menu bar when something on your Mac changes."))
            }
            ForEach($manager.rules) { $rule in
                SettingsModuleRow(
                    Text(verbatim: rule.name),
                    summary: Text(verbatim: AutomationDescription.sentence(for: rule)),
                    systemImage: symbol(for: rule.action),
                    isOn: $rule.isEnabled,
                    isOpen: isOpen(rule.id)
                ) {
                    AutomationRuleEditor(
                        rule: $rule,
                        profileNames: profileNames,
                        focusesName: rule.id == focusedNewRuleID
                    ) {
                        deletionID = rule.id
                    }
                }
            }
            SettingsButtonRow(unlabeled: .automationAddRule) {
                Button("Add rule…") {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .tint(HolzBarTheme.Palette.accent)
                .disabled(manager.rules.count >= AutomationRule.maximumCount)
            }
            SettingsNoteLine(Text("To apply a layout profile with a Focus, add the holzBar filter to that Focus in System Settings."))
        }
    }

    /// Whether the editor of the rule is open; one rule is open at a time.
    private func isOpen(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { editingID == id },
            set: { isOpen in
                focusedNewRuleID = nil
                editingID = isOpen ? id : (editingID == id ? nil : editingID)
            }
        )
    }

    private func symbol(for action: AutomationAction) -> String {
        switch action {
        case .applyProfile: "rectangle.stack"
        case .applyMood: "paintpalette"
        case .showSection: "eye"
        case .zen: "moon"
        case .keepAwake: "cup.and.saucer"
        case .showItemOnlyWhile: "eye.slash"
        case .runScript: "terminal"
        }
    }

    private func addRule() {
        guard manager.rules.count < AutomationRule.maximumCount else {
            return
        }
        let name = String(localized: "New Rule")
        let id = manager.addRule(named: name, profileName: profileNames.first)
        editingID = id
        focusedNewRuleID = id
    }
}
