//
//  AccessoryAlertsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessory alerts module's settings, shown under its row in the Modules pane while the
/// module is on: a switch for connect alerts and one for disconnect alerts, the three settings
/// of the battery half (reading levels, the low-battery alert and its level), and the state of
/// the Bluetooth permission.
///
/// The view only flips stored values and reads the permission; the question itself is asked by
/// the running module when it starts, never from here. A change of a battery setting tells the
/// running module, which reads again.
struct AccessoryAlertsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AccessoryAlertsSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Alert when an accessory connects", isOn: $settings.connect)
            caption(Text("A capsule below the notch names the accessory for five seconds."))
            Toggle("Alert when an accessory disconnects", isOn: $settings.disconnect)
            caption(Text("Off by default, because AirPods disconnect whenever they go back in their case."))
            Toggle("Read battery levels", isOn: $settings.readsBattery)
            caption(Text("Uses a macOS call that Apple does not document, so it may stop working in a later macOS. Nothing is sent anywhere."))
            Toggle("Alert when the battery is low", isOn: $settings.lowBattery)
                .disabled(!settings.readsBattery)
            Stepper(value: $settings.lowBatteryLevel, in: AccessoryAlertOptions.lowBatteryLevelRange, step: 5) {
                HStack {
                    Text("Low battery level")
                    Spacer()
                    Text(verbatim: AccessoryBattery.percentText(settings.lowBatteryLevel))
                        .monospacedDigit()
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            }
            .disabled(!settings.readsBattery || !settings.lowBattery)
            switch access {
            case .denied:
                deniedAccess
            case .notDetermined:
                caption(Text("macOS asks for Bluetooth when the Notch hub is on."))
            case .allowed:
                EmptyView()
            }
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
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

    private var runtime: AccessoryAlertsRuntime? {
        appState.notchHub.runtime(AccessoryAlertsRuntime.self)
    }

    /// What macOS lets holzBar do with Bluetooth: the running module's last finding, or the
    /// system's answer while the module does not run.
    private var access: BluetoothAccess {
        runtime?.access ?? BluetoothDeviceMonitor.access
    }

    /// The sentence and the button of a refused permission; nothing asks again by itself.
    private var deniedAccess: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Text("holzBar may not use Bluetooth, so connection alerts are off.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Bluetooth Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
