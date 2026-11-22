//
//  ReadoutsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The System readouts module's settings, in the open area of the module's row: which tiles show,
/// whether the CPU tile carries the thermal state line, how often the tiles read, and how the
/// network speed counts. The view shows no reading of any kind: a live preview here would be a
/// sampling consumer, and the module reads nothing while its settings are open.
struct ReadoutsSettingsView: View {
    @Environment(AppState.self) private var appState

    /// Whether this Mac has an internal battery, asked once when the view first appears and never
    /// again while it is open. `nil` until then, so the Battery tile row waits for the answer.
    @State private var hasBattery: Bool?

    var body: some View {
        @Bindable var settings = appState.settings.readouts
        let isModuleOn = appState.modules.isEnabled(ReadoutsSettings.moduleID)
        Group {
            SettingsToggleRow(.modulesReadoutsTileCPU, isOn: tileBinding(.cpu))
            SettingsToggleRow(
                .modulesReadoutsThermalState,
                isOn: Binding(
                    get: { settings.showsThermalLine },
                    set: { settings.setThermalLine($0) }
                )
            )
            .settingsSubRow()
            .settingsDependent(on: settings.isOn(.cpu))
            SettingsToggleRow(.modulesReadoutsTileMemory, isOn: tileBinding(.memory))
            SettingsToggleRow(.modulesReadoutsTileNetwork, isOn: tileBinding(.network))
            SettingsToggleRow(.modulesReadoutsTileDisk, isOn: tileBinding(.disk))
            if hasBattery == true {
                SettingsToggleRow(.modulesReadoutsTileBattery, isOn: tileBinding(.battery))
            }
            SettingsPickerRow(.modulesReadoutsTileRefresh, selection: $settings.tileRefreshSeconds) {
                ForEach(ReadoutTileRefresh.choices, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
        }
        .settingsDependent(on: isModuleOn)
        // Not dependent on the module switch: the unit serves the Network Speed widget too.
        SettingsPickerRow(.modulesReadoutsRateUnit, selection: $settings.rateUnit) {
            ForEach(ReadoutRateUnit.allCases, id: \.self) { unit in
                Text(unit.localized).tag(unit)
            }
        }
        .onAppear {
            if hasBattery == nil {
                hasBattery = PowerSources.internalBattery() != nil
            }
        }
    }

    /// The switch of one tile.
    private func tileBinding(_ kind: ReadoutTileKind) -> Binding<Bool> {
        let settings = appState.settings.readouts
        return Binding(
            get: { settings.isOn(kind) },
            set: { settings.setTile(kind, on: $0) }
        )
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
