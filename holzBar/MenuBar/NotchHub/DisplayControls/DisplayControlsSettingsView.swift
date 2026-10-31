//
//  DisplayControlsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Display controls module's settings, shown under its row in the Modules pane while the
/// module is on: one switch for the brightness sliders, which use a private macOS interface.
/// Turning it off keeps that interface from ever being loaded. The view only flips the stored
/// switch; the running module reads it each time the hub opens.
struct DisplayControlsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.displayControls
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Brightness", isOn: $settings.showsBrightness)
            Text("Uses a private macOS interface. It switches itself off if macOS changes it.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }
}
