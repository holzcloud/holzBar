//
//  TimersSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Timers module's setting, shown under its row in the Modules pane while the module is
/// on: the sound that rings when a timer ends, and a button that plays it.
struct TimersSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.timers
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            HolzBarPicker("Finish sound", selection: $settings.finishSound) {
                ForEach(TimerFinishSound.allCases, id: \.self) { sound in
                    label(of: sound).tag(sound)
                }
            }
            Button("Play") {
                preview.playFinishSound(settings.finishSound)
            }
            .disabled(settings.finishSound == .none)
        }
    }

    /// Plays the sound for the button. It holds no timer and no observer.
    @State private var preview = TimersAlarm()

    /// The sounds carry the system's own names in every language; only "None" is translated.
    private func label(of sound: TimerFinishSound) -> Text {
        if let name = sound.systemName {
            Text(verbatim: name)
        } else {
            Text("None")
        }
    }
}
