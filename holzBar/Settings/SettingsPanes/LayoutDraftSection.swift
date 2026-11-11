//
//  LayoutDraftSection.swift
//  holzBar
//

import SwiftUI

/// The group Changes of the Layout pane: the changes that wait for Apply, the outcome of the last
/// Apply, and the settings for how changes apply.
struct LayoutDraftSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let editor = appState.layoutEditor
        let general = Bindable(appState.settings.general)
        SettingsGroup(SettingsCatalog.LayoutPane.changes) {
            if editor.isChanged || editor.isApplying {
                waitingRow(of: editor)
            } else if let outcome = editor.outcome {
                SettingsStateLine(.success, Text("Changes applied: \(outcome.applied)"))
                if outcome.leftToRules > 0 {
                    SettingsStateLine(.info, Text("Left to their rules: \(outcome.leftToRules)"))
                }
                if outcome.failed > 0 {
                    SettingsStateLine(.warning, Text("Could not be moved: \(outcome.failed)"))
                }
            } else if appState.settings.general.appliesLayoutChangesImmediately {
                SettingsStateLine(.info, Text("Every move happens at once."))
            }
            SettingsToggleRow(.layoutApplyImmediately, isOn: general.appliesLayoutChangesImmediately)
                .onChange(of: appState.settings.general.appliesLayoutChangesImmediately) { _, isImmediate in
                    // What waits is applied, so no change is left behind a switch.
                    if isImmediate {
                        editor.apply()
                    }
                }
            if MenuBarBackendKind.current == .accessibility27 {
                SettingsToggleRow(
                    .layoutCommandDragSetsSection,
                    isOn: general.commandDragSetsSection,
                    badge: .preview
                )
            }
        }
    }

    private func waitingRow(of editor: LayoutEditor) -> some View {
        SettingsButtonRow(
            editor.isApplying ? Text("Applying…") : Text("Changes waiting: \(editor.changeCount)")
        ) {
            if editor.isApplying {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Discard") {
                editor.discard()
            }
            .disabled(editor.isApplying)
            Button("Apply") {
                editor.apply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(editor.isApplying)
        }
    }
}

/// The tile "New items" in the section where items holzBar has never seen land, with the choice
/// of another section.
struct NewItemsTile: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let editor = appState.layoutEditor
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            HolzBarPicker(selection: Binding(
                get: { editor.newItemsSection },
                set: { editor.setNewItemsSection($0) }
            )) {
                ForEach(editor.availableSections, id: \.self) { section in
                    Text(section.localized).tag(section)
                }
            } label: {
                Label("New items", systemImage: "sparkles")
            }
            Text("Items holzBar has not seen before land in this section.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HolzBarTheme.Spacing.md)
    }
}
