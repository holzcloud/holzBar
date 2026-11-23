//
//  IndicatorsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Indicators module's settings, in the open area of the module's row: the Input source
/// switch, with its Show for choice as a dependent sub row, and a line that says so while only one
/// input source is enabled, because then there is nothing to switch between and nothing flashes;
/// then the Volume and brightness switch, with its Replace the system display sub row. Turning the
/// last one on is the only moment holzBar asks for Accessibility; while it is on and the permission
/// is missing, a warning line says so and opens System Settings.
///
/// The view only flips stored values and reads how many input sources are enabled once, when it
/// appears (and the Accessibility flag when Settings becomes active); it observes nothing else and
/// the running module is the one that listens to the system.
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
        SettingsToggleRow(.modulesIndicatorsVolumeBrightness, isOn: $settings.showsVolumeBrightness, badge: .preview)
        SettingsToggleRow(
            .modulesIndicatorsReplacesSystemDisplay,
            isOn: replacesBinding,
            small: Text("private interface"),
            badge: .preview
        )
        .settingsSubRow()
        .settingsDependent(on: settings.showsVolumeBrightness)
        .task {
            // Accessibility can be granted or taken away in System Settings while this window waits.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                appState.permissions.accessibility.refresh()
            }
        }
        if settings.replacesSystemDisplay, !appState.permissions.accessibility.hasPermission {
            SettingsStateLine(.warning, Text("Accessibility access is off")) {
                Button("Open System Settings") {
                    appState.permissions.accessibility.openSettings()
                }
            }
        }
    }

    /// The Replace the system display switch. Turning it on asks for Accessibility when holzBar
    /// does not hold it yet: this is the only place that asks. Denied or revoked, the switch stays
    /// as the user set it and no tap exists.
    private var replacesBinding: Binding<Bool> {
        Binding {
            appState.settings.indicators.replacesSystemDisplay
        } set: { isOn in
            appState.settings.indicators.replacesSystemDisplay = isOn
            if isOn, !appState.permissions.accessibility.hasPermission {
                appState.permissions.accessibility.performRequest()
            }
        }
    }
}
