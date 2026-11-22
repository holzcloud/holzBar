//
//  SystemAlertsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The System alerts module's settings, in the open area of the module's row: the five fixed
/// rules in the order of the contract, each a switch with its threshold or level and how long the
/// condition has to hold as dependent sub rows. The rows dim while the module is off and a rule's
/// sub rows dim while the rule is off. The view only flips stored values: it runs and measures
/// nothing, so it also works while the Notch hub and System readouts are off.
struct SystemAlertsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let settings = appState.settings.systemAlerts
        let isModuleOn = appState.modules.isEnabled(SystemAlertsSettings.moduleID)
        Group {
            SettingsToggleRow(.modulesSystemAlertsCPU, isOn: isOnBinding(.cpu))
            SettingsStepperRow(
                .modulesSystemAlertsCPUThreshold,
                value: limitBinding(.cpu),
                in: ThresholdRule.cpuLimits,
                step: ThresholdRule.limitStep
            ) { limit in
                Text(verbatim: AlertTexts.limitText(limit, for: .cpu))
            }
            .settingsSubRow()
            .settingsDependent(on: settings.rule(for: .cpu).isOn)
            holdRow(.modulesSystemAlertsCPUDuration, for: .cpu)
        }
        .settingsDependent(on: isModuleOn)
    }

    /// The "Held for" row of a rule: a sub row of the rule's switch.
    private func holdRow(_ entry: SettingsEntry, for signal: AlertSignal) -> some View {
        SettingsPickerRow(entry, selection: holdBinding(signal)) {
            ForEach(AlertHold.allCases, id: \.self) { hold in
                Text(verbatim: AlertTexts.holdText(hold)).tag(hold)
            }
        }
        .settingsSubRow()
        .settingsDependent(on: appState.settings.systemAlerts.rule(for: signal).isOn)
    }

    private func isOnBinding(_ signal: AlertSignal) -> Binding<Bool> {
        let settings = appState.settings.systemAlerts
        return Binding(
            get: { settings.rule(for: signal).isOn },
            set: { settings.setOn($0, for: signal) }
        )
    }

    private func limitBinding(_ signal: AlertSignal) -> Binding<Int> {
        let settings = appState.settings.systemAlerts
        return Binding(
            get: { settings.rule(for: signal).limit },
            set: { settings.setLimit($0, for: signal) }
        )
    }

    private func holdBinding(_ signal: AlertSignal) -> Binding<AlertHold> {
        let settings = appState.settings.systemAlerts
        return Binding(
            get: { settings.rule(for: signal).hold },
            set: { settings.setHold($0, for: signal) }
        )
    }
}
