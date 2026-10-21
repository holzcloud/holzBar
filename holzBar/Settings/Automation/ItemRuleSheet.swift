//
//  ItemRuleSheet.swift
//  holzBar
//

import SwiftUI

/// The rule of one menu bar item, opened from the item's menu in Menu Bar Layout: "show this
/// item only while …". It is the editor of Automation rules with the action fixed, so an item
/// rule is an ordinary rule that also shows in the Automation pane.
struct ItemRuleSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let target: ItemRuleTarget
    @State private var rule: AutomationRule?

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Show Only When…")
                .font(HolzBarTheme.Typography.title)
                .accessibilityAddTraits(.isHeader)
            Text("\(target.name) is moved into a hidden section while the conditions do not hold, and back to where you had it while they do. A move by hand lasts only while they hold. Nothing happens while a condition cannot be read. A profile leaves this item where its rule puts it.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let binding = Binding($rule) {
                ScrollView {
                    AutomationRuleEditor(
                        rule: binding,
                        profileNames: [],
                        focusesName: false,
                        itemName: target.name
                    ) {
                        appState.automation.removeItemRule(forKey: target.key)
                        dismiss()
                    }
                }
                .frame(minHeight: 220, maxHeight: 360)
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if let rule {
                        appState.automation.saveItemRule(rule)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!(rule?.isValid ?? false))
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 460)
        .task {
            guard rule == nil else {
                return
            }
            rule = appState.automation.itemRule(forKey: target.key)
                ?? appState.automation.newItemRule(forKey: target.key, itemName: target.name)
        }
    }
}
