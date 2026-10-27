//
//  MoodsSection.swift
//  holzBar
//

import SwiftUI

/// Saved looks of the menu bar: save the look that is on now, switch to another with one click.
/// A rule (time of day, a display) or the command palette can switch moods too.
struct MoodsSection: View {
    @Bindable var appearanceManager: MenuBarAppearanceManager
    @State private var isAskingForName = false
    @State private var newName = ""

    private var canSave: Bool {
        appearanceManager.moods.count < MoodNaming.maximumCount
    }

    var body: some View {
        HolzBarSection {
            Text("Moods")
                .font(.headline)
        } content: {
            ForEach(appearanceManager.moods) { mood in
                row(for: mood)
            }
            HStack {
                Button("Save Current Look…", systemImage: "plus") {
                    newName = ""
                    isAskingForName = true
                }
                .disabled(!canSave)
                if appearanceManager.moods.isEmpty {
                    Text("Save a look to switch back to it in one click, or from a rule.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                }
                Spacer()
            }
        }
        .alert("Save Current Look", isPresented: $isAskingForName) {
            TextField("Name", text: $newName)
            Button("Save") {
                appearanceManager.saveCurrentLook(named: newName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give the look of the menu bar a name.")
        }
    }

    private func row(for mood: AppearanceMood) -> some View {
        let isCurrent = mood.name == appearanceManager.currentMoodName
        return HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCurrent ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textTertiary)
                .accessibilityHidden(true)
            Text(verbatim: mood.name)
            Spacer()
            Button("Apply") {
                appearanceManager.applyMood(named: mood.name)
            }
            .disabled(isCurrent)
            Button {
                appearanceManager.removeMood(withID: mood.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            .accessibilityLabel(Text("Delete Mood"))
            .help("Delete Mood")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: mood.name))
        .accessibilityValue(isCurrent ? Text("In use") : Text(""))
    }
}
