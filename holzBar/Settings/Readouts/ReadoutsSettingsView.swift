//
//  ReadoutsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The System readouts module's settings, in the open area of the module's row: how the network
/// speed counts. The view shows no reading of any kind: a live preview here would be a sampling
/// consumer, and the module reads nothing while its settings are open.
struct ReadoutsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.readouts
        // Not dependent on the module switch: the unit serves the Network Speed widget too.
        SettingsPickerRow(.modulesReadoutsRateUnit, selection: $settings.rateUnit) {
            ForEach(ReadoutRateUnit.allCases, id: \.self) { unit in
                Text(unit.localized).tag(unit)
            }
        }
    }
}

private extension ReadoutRateUnit {
    /// The choice's name in the picker.
    var localized: LocalizedStringKey {
        switch self {
        case .bytes: "Bytes per second"
        case .bits: "Bits per second"
        }
    }
}
