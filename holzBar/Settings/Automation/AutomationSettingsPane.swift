//
//  AutomationSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The rules: "when this is true, do that". One glass group, one row per rule; the editor of
/// a rule opens under its row.
struct AutomationSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var manager: AutomationManager
    @State private var editingID: UUID?
    @State private var deletionID: UUID?

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
        HolzBarForm(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                PreviewBadge()
                Text("Preview: not tested on a Mac yet. Please report problems.")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            Text("When something happens, holzBar changes the menu bar for you. With no rules, nothing is observed.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !manager.rules.isEmpty {
                ruleList
            }
            Text("To apply a layout profile with a Focus, add the holzBar filter to that Focus in System Settings.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Button("Add Rule", systemImage: "plus") {
                    addRule()
                }
                Text("Rules are stored on this Mac.")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            }
        }
        .confirmationDialog("Delete this rule?", isPresented: isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deletionID {
                    if editingID == id {
                        editingID = nil
                    }
                    manager.removeRule(withID: id)
                }
                deletionID = nil
            }
            Button("Cancel", role: .cancel) {
                deletionID = nil
            }
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            ForEach($manager.rules) { $rule in
                ModuleRow(
                    systemImage: symbol(for: rule.action),
                    title: Text(verbatim: rule.name),
                    summary: Text(verbatim: AutomationDescription.sentence(for: rule)),
                    isOn: $rule.isEnabled,
                    showsSettings: editingID == rule.id,
                    onSelect: {
                        editingID = editingID == rule.id ? nil : rule.id
                    },
                    settings: {
                        AutomationRuleEditor(rule: $rule, profileNames: profileNames) {
                            deletionID = rule.id
                        }
                    }
                )
                if rule.id != manager.rules.last?.id {
                    Divider()
                        .overlay(HolzBarTheme.Palette.stroke)
                }
            }
        }
        .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
        .holzBarGlass(in: HolzBarTheme.shape(HolzBarTheme.Radius.card))
    }

    private func symbol(for action: AutomationAction) -> String {
        switch action {
        case .applyProfile: "rectangle.stack"
        case .showSection: "eye"
        case .zen: "moon"
        }
    }

    private func addRule() {
        guard manager.rules.count < AutomationRule.maximumCount else {
            return
        }
        let name = String(localized: "New Rule")
        editingID = manager.addRule(named: name, profileName: profileNames.first)
    }
}
