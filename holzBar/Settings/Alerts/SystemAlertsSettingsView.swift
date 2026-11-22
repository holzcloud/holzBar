//
//  SystemAlertsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The System alerts module's settings, in the open area of the module's row: first the System
/// notifications switch (off by default; macOS asks for permission when it goes on, and a line with
/// a way to System Settings shows when macOS says no), then the five fixed
/// rules in the order of the contract (CPU load, memory pressure, thermal state, free disk space,
/// Mac battery), each a switch with its threshold or level and how long the condition has to hold
/// as dependent sub rows. The rows dim while the module is off and a rule's sub rows dim while the
/// rule is off. The Mac battery rows are left out on a Mac without an internal battery. With the
/// module on and every shown rule off, one line says so. The Test alert button comes last: it
/// shows a sample alert whatever the rules say.
///
/// The view only flips stored values and starts the sample: it measures nothing, so it also works
/// while the Notch hub and System readouts are off.
struct SystemAlertsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let isModuleOn = appState.modules.isEnabled(SystemAlertsSettings.moduleID)
        Group {
            SettingsToggleRow(
                .modulesSystemAlertsNotifications,
                isOn: notificationsBinding,
                small: Text("needs Notifications")
            )
            if appState.settings.systemAlerts.notificationsOn, appState.systemAlerts.notificationAccess == .denied {
                SettingsStateLine(.warning, Text("Notifications are off for holzBar")) {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            SettingsToggleRow(.modulesSystemAlertsCPU, isOn: isOnBinding(.cpu))
            stepperRow(.modulesSystemAlertsCPUThreshold, for: .cpu, in: ThresholdRule.cpuLimits)
            holdRow(.modulesSystemAlertsCPUDuration, for: .cpu)

            SettingsToggleRow(.modulesSystemAlertsMemoryPressure, isOn: isOnBinding(.memoryPressure))
            menuRow(.modulesSystemAlertsMemoryPressureThreshold, for: .memoryPressure, choices: Array(ThresholdRule.memoryLevels))
            holdRow(.modulesSystemAlertsMemoryPressureDuration, for: .memoryPressure)

            SettingsToggleRow(.modulesSystemAlertsThermal, isOn: isOnBinding(.thermal))
            menuRow(.modulesSystemAlertsThermalThreshold, for: .thermal, choices: Array(ThresholdRule.thermalLevels))
            holdRow(.modulesSystemAlertsThermalDuration, for: .thermal)

            SettingsToggleRow(.modulesSystemAlertsFreeDisk, isOn: isOnBinding(.freeDisk))
            menuRow(.modulesSystemAlertsFreeDiskThreshold, for: .freeDisk, choices: ThresholdRule.diskLimitsGB)
            holdRow(.modulesSystemAlertsFreeDiskDuration, for: .freeDisk)

            if SystemAlertsSettings.hasInternalBattery {
                SettingsToggleRow(
                    .modulesSystemAlertsMacBattery,
                    isOn: isOnBinding(.macBattery),
                    small: Text("on battery only")
                )
                stepperRow(.modulesSystemAlertsMacBatteryThreshold, for: .macBattery, in: ThresholdRule.batteryLimits)
                holdRow(.modulesSystemAlertsMacBatteryDuration, for: .macBattery)
            }
        }
        .settingsDependent(on: isModuleOn)
        if isModuleOn, !shownRules.contains(where: \.isOn) {
            SettingsStateLine(.info, Text("No alert rule is switched on"))
        }
        SettingsButtonRow(unlabeled: .modulesSystemAlertsTest) {
            Button("Test alert") {
                appState.systemAlerts.showTestAlert()
            }
        }
        .settingsDependent(on: isModuleOn)
    }

    /// The rules the settings show: all five, or four on a Mac without an internal battery.
    private var shownRules: [ThresholdRule] {
        appState.settings.systemAlerts.rules.filter {
            $0.signal != .macBattery || SystemAlertsSettings.hasInternalBattery
        }
    }

    /// A threshold in steps of five: CPU load and the Mac battery. A sub row of the rule's switch.
    private func stepperRow(_ entry: SettingsEntry, for signal: AlertSignal, in range: ClosedRange<Int>) -> some View {
        SettingsStepperRow(
            entry,
            value: limitBinding(signal),
            in: range,
            step: ThresholdRule.limitStep
        ) { limit in
            Text(verbatim: AlertTexts.limitText(limit, for: signal))
        }
        .settingsSubRow()
        .settingsDependent(on: appState.settings.systemAlerts.rule(for: signal).isOn)
    }

    /// A threshold from a short menu: a level, or a disk size. A sub row of the rule's switch.
    private func menuRow(_ entry: SettingsEntry, for signal: AlertSignal, choices: [Int]) -> some View {
        SettingsPickerRow(entry, selection: limitBinding(signal)) {
            ForEach(choices, id: \.self) { choice in
                Text(verbatim: AlertTexts.limitText(choice, for: signal)).tag(choice)
            }
        }
        .settingsSubRow()
        .settingsDependent(on: appState.settings.systemAlerts.rule(for: signal).isOn)
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

    private var notificationsBinding: Binding<Bool> {
        let settings = appState.settings.systemAlerts
        return Binding(
            get: { settings.notificationsOn },
            set: { settings.notificationsOn = $0 }
        )
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
