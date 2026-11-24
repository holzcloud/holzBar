//
//  LayoutMakingRoomGroups.swift
//  holzBar
//

import SwiftUI

/// The group Making room of the Layout pane (Phase 97, D-10, D-12, concept M7): what holzBar does
/// when macOS 27 folds items away because the bar is full, and whether it asks where a new app
/// goes. The two rows are independent and neither dims the other; both apply at once.
///
/// The group exists only on macOS 27, where the Layout pane has the fit model.
@available(macOS 27.0, *)
struct MakingRoomGroup: View {
    @Bindable var advanced: AdvancedSettings

    var body: some View {
        SettingsGroup(SettingsCatalog.LayoutPane.makingRoom) {
            SettingsPickerRow(.layoutMakeRoomMode, selection: $advanced.makeRoomMode, badge: .preview) {
                Text(MakeRoomMode.off.localized).tag(MakeRoomMode.off)
                Text(MakeRoomMode.ask.localized).tag(MakeRoomMode.ask)
                Text(MakeRoomMode.automatic.localized).tag(MakeRoomMode.automatic)
            }
            SettingsToggleRow(.layoutAsksWhereNewAppGoes, isOn: $advanced.asksWhereNewAppGoes, badge: .preview)
        }
    }
}

/// The group New apps of the Layout pane (Phase 97, D-12, COMF-04): one row for each app that
/// macOS 27 showed in the menu bar for the first time while "Ask where a new app goes" is on.
/// Choosing a section moves the app at once as one Undo step, and the row leaves.
///
/// The group exists only while the switch is on and an app is asked about. Always Hidden is
/// offered only while that section is enabled.
@available(macOS 27.0, *)
struct NewAppsGroup: View {
    let questions: NewAppQuestions27?
    let advanced: AdvancedSettings

    var body: some View {
        if advanced.asksWhereNewAppGoes, let questions, !questions.asked.isEmpty {
            SettingsGroup(SettingsCatalog.LayoutPane.newApps) {
                ForEach(questions.asked) { app in
                    SettingsPickerRow(Text(verbatim: app.name), selection: binding(for: app, in: questions), badge: .preview) {
                        Text("Choose…").tag(nil as NewAppQuestion.Answer?)
                        Text("Visible").tag(NewAppQuestion.Answer.visible as NewAppQuestion.Answer?)
                        Text("Hidden").tag(NewAppQuestion.Answer.hidden as NewAppQuestion.Answer?)
                        if questions.offersAlwaysHidden {
                            Text("Always Hidden").tag(NewAppQuestion.Answer.alwaysHidden as NewAppQuestion.Answer?)
                        }
                        Text("Don't ask again").tag(NewAppQuestion.Answer.dontAskAgain as NewAppQuestion.Answer?)
                    }
                }
            }
        }
    }

    /// The pop-up always reads "Choose…"; choosing a section answers and the row leaves.
    private func binding(for app: NewAppQuestion.App, in questions: NewAppQuestions27) -> Binding<NewAppQuestion.Answer?> {
        Binding(
            get: { nil },
            set: { answer in
                if let answer {
                    questions.answer(answer, for: app.bundleID, place: .settings)
                }
            }
        )
    }
}
