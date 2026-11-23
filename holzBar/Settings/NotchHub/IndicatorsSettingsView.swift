//
//  IndicatorsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Indicators module's settings, in the open area of the module's row: the Input source
/// switch. The view only flips the stored value; the running module is the one that listens to the
/// system.
struct IndicatorsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.indicators
        SettingsToggleRow(.modulesIndicatorsInputSource, isOn: $settings.showsInputSource, badge: .preview)
    }
}
