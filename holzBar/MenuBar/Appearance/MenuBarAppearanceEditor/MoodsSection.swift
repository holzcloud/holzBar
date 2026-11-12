//
//  MoodsSection.swift
//  holzBar
//

import SwiftUI

/// Saved looks of the menu bar: save the look that is on now, switch to another with one click.
/// A rule (time of day, a display) or the command palette can switch moods too.
struct MoodsSection: View {
    @Environment(AppState.self) private var appState
    @Bindable var appearanceManager: MenuBarAppearanceManager
    /// Where the undo toast of a deletion shows: Settings or the floating editor.
    let place: LayoutUndo.Place
    @State private var isAskingForName = false
    @State private var newName = ""

    private var canSave: Bool {
        appearanceManager.moods.count < MoodNaming.maximumCount
    }

    var body: some View {
        SettingsGroup(
            SettingsCatalog.AppearancePane.moods,
            footnote: Text("At most \(MoodNaming.maximumCount) moods. A name has up to \(MoodNaming.maximumNameLength) characters.")
        ) {
            if appearanceManager.moods.isEmpty {
                SettingsEmptyRow(systemImage: "paintpalette", Text("No moods yet: save the current look to switch to it in one click."))
            }
            ForEach(appearanceManager.moods) { mood in
                row(for: mood)
            }
            SettingsButtonRow(unlabeled: .appearanceSaveCurrentLook) {
                Button("Save Current Look…") {
                    newName = ""
                    isAskingForName = true
                }
                .disabled(!canSave)
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

    /// The name is user data, so the row uses the text form; the trash acts at once (D-10).
    private func row(for mood: AppearanceMood) -> some View {
        let isCurrent = mood.name == appearanceManager.currentMoodName
        return SettingsButtonRow(Text(verbatim: mood.name), small: isCurrent ? Text("In use") : nil) {
            Button("Apply") {
                appearanceManager.applyMood(named: mood.name)
            }
            .disabled(isCurrent)
            Button(role: .destructive) {
                guard let removed = appearanceManager.removeMood(withID: mood.id) else {
                    return
                }
                let manager = appearanceManager
                appState.layoutUndo.recordDeletion(
                    String(localized: "\u{201C}\(mood.name)\u{201D} deleted"),
                    place: place,
                    restore: { manager.insertMood(removed.mood, at: removed.index, makeCurrent: removed.wasCurrent) },
                    deleteAgain: { manager.removeMood(withID: removed.mood.id) }
                )
            } label: {
                Label("Delete Mood", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Delete Mood")
        }
    }
}
