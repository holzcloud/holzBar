//
//  IndicatorsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Indicators module's settings, in the open area of the module's row: the Input source
/// switch, with its Show for choice as a dependent sub row, and a line that says so while only one
/// input source is enabled, because then there is nothing to switch between and nothing flashes.
///
/// The view only flips stored values and reads how many input sources are enabled once, when it
/// appears; it observes nothing and the running module is the one that listens to the system.
struct IndicatorsSettingsView: View {
    @Environment(AppState.self) private var appState

    /// How many input sources were enabled when the view appeared, or `nil` before that.
    @State private var enabledSourceCount: Int?

    var body: some View {
        @Bindable var settings = appState.settings.indicators
        SettingsToggleRow(.modulesIndicatorsInputSource, isOn: $settings.showsInputSource, badge: .preview)
        if settings.showsInputSource, let count = enabledSourceCount, !InputSourceLabel.shows(enabledCount: count) {
            SettingsStateLine(.info, Text("Only one input source is enabled"))
        }
        SettingsPickerRow(.modulesIndicatorsInputSourceDuration, selection: $settings.inputSourceDuration) {
            ForEach(DesignTokens.Indicator.inputSourceDurations, id: \.self) { seconds in
                Text(
                    Measurement(value: seconds, unit: UnitDuration.seconds),
                    format: .measurement(width: .abbreviated, usage: .asProvided)
                )
                .tag(seconds)
            }
        }
        .settingsSubRow()
        .settingsDependent(on: settings.showsInputSource)
        .onAppear {
            enabledSourceCount = InputSourceObserver.enabledCount()
        }
    }
}
