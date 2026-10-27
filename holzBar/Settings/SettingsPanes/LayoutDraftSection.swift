//
//  LayoutDraftSection.swift
//  holzBar
//

import SwiftUI

/// The strip above the rows of the Menu Bar Layout pane: the changes that wait for Apply, with
/// Apply and Discard, and the setting that makes every move happen at once.
struct LayoutDraftSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let editor = appState.layoutEditor
        let general = Bindable(appState.settings.general)
        HolzBarSection {
            if editor.isChanged || editor.isApplying {
                changes(of: editor)
            } else if let outcome = editor.outcome {
                result(of: outcome)
            }
            Toggle(isOn: general.appliesLayoutChangesImmediately) {
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Text("Apply changes immediately")
                    PreviewBadge()
                }
            }
            .annotation("Off: dragging an item only changes the drawing below, and the menu bar follows when you choose Apply. On: every move happens at once.")
            .onChange(of: appState.settings.general.appliesLayoutChangesImmediately) { _, isImmediate in
                // What waits is applied, so no change is left behind a switch.
                if isImmediate {
                    editor.apply()
                }
            }
        }
    }

    private func changes(of editor: LayoutEditor) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            if editor.isApplying {
                ProgressView()
                    .controlSize(.small)
                Text("Applying…")
            } else {
                Text("Changes waiting: \(editor.changeCount)")
            }
            Spacer()
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
        .padding(HolzBarTheme.Spacing.md)
        .accessibilityElement(children: .contain)
    }

    private func result(of outcome: LayoutEditor.Outcome) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            Text("Changes applied: \(outcome.applied)")
            if outcome.leftToRules > 0 {
                Text("Left to their rules: \(outcome.leftToRules)")
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            if outcome.failed > 0 {
                Text("Could not be moved: \(outcome.failed)")
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HolzBarTheme.Spacing.md)
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
