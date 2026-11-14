//
//  AccessoryAlertsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessory alerts module's settings, in the open area of the module's row: a switch for
/// connect alerts and one for disconnect alerts, the three settings of the battery half (reading
/// levels, labelled as a private interface, the low-battery alert and its level as dependent sub
/// rows), and the state of the Bluetooth permission.
///
/// The view only flips stored values and reads states; the Bluetooth question is asked by the
/// running module when it starts, never from here, and whether battery reading switched itself
/// off comes from the running module too. A change of a battery setting tells the running
/// module, which reads again.
struct AccessoryAlertsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AccessoryAlertsSettings()

    var body: some View {
        // A container only so that the three change handlers run once.
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(
                .modulesAccessoryAlertsConnect,
                isOn: $settings.connect,
                info: access == .notDetermined
                    ? Text("The notch widens for five seconds and shows the accessory's symbol. macOS asks for Bluetooth when the Notch hub is on.")
                    : nil
            )
            SettingsToggleRow(.modulesAccessoryAlertsDisconnect, isOn: $settings.disconnect)
            if access == .denied {
                SettingsStateLine(.warning, Text("Bluetooth access is off")) {
                    Button("Open Bluetooth Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            SettingsToggleRow(
                .modulesAccessoryAlertsReadsBattery,
                isOn: $settings.readsBattery,
                small: Text("private interface")
            )
            if batteryReadingSwitchedOff {
                SettingsStateLine(.warning, Text("Battery levels are not available on this Mac"))
            }
            SettingsToggleRow(.modulesAccessoryAlertsLowBattery, isOn: $settings.lowBattery)
                .settingsSubRow()
                .settingsDependent(on: settings.readsBattery)
            SettingsStepperRow(
                .modulesAccessoryAlertsLowBatteryLevel,
                value: $settings.lowBatteryLevel,
                in: AccessoryAlertOptions.lowBatteryLevelRange,
                step: 5
            ) { level in
                Text(verbatim: AccessoryBattery.percentText(level))
            }
            .settingsSubRow()
            .settingsDependent(on: settings.readsBattery && settings.lowBattery)
        }
        .onChange(of: settings.readsBattery) {
            runtime?.settingsDidChange()
        }
        .onChange(of: settings.lowBattery) {
            runtime?.settingsDidChange()
        }
        .onChange(of: settings.lowBatteryLevel) {
            runtime?.settingsDidChange()
        }
    }

    /// Whether battery reading is on and the running module found the undocumented call
    /// missing or failing. Settings never looks the call up itself.
    private var batteryReadingSwitchedOff: Bool {
        settings.readsBattery && (runtime?.batteryReadingUnavailable ?? false)
    }

    private var runtime: AccessoryAlertsRuntime? {
        appState.notchHub.runtime(AccessoryAlertsRuntime.self)
    }

    /// What macOS lets holzBar do with Bluetooth: the running module's last finding, or the
    /// system's answer while the module does not run.
    private var access: BluetoothAccess {
        runtime?.access ?? BluetoothDeviceMonitor.access
    }
}
