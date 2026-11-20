//
//  DisplayControlsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Display controls module's settings, in the open area of the module's row: one switch for
/// the brightness sliders and one for the external monitors, each labelled as a private
/// interface (the second also as Preview). Turning one off keeps its interface from ever being
/// loaded. The state lines follow the running module's own start check; nothing is loaded or
/// looked up from here.
struct DisplayControlsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.displayControls
        SettingsToggleRow(
            .modulesDisplayControlsBrightness,
            isOn: $settings.showsBrightness,
            small: Text("private interface")
        )
        if settings.showsBrightness, brightnessSwitchedItselfOff {
            SettingsStateLine(.warning, Text("Brightness is not available on this Mac"))
        }
        SettingsToggleRow(
            .modulesDisplayControlsExternalMonitors,
            isOn: $settings.showsExternalMonitors,
            small: Text("private interface"),
            badge: .preview
        )
    }

    /// Whether the running module's start check switched brightness off. With the hub or the
    /// module off there is no runtime, and nothing is shown.
    private var brightnessSwitchedItselfOff: Bool {
        guard let state = appState.notchHub.runtime(DisplayControlsRuntime.self)?.gate.state else {
            return false
        }
        if case .unavailable(let reason) = state, reason != .switchedOff {
            return true
        }
        return false
    }
}
