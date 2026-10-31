//
//  AccessoryAlertsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessory alerts module's settings, shown under its row in the Modules pane while the
/// module is on: a switch for connect alerts and one for disconnect alerts, and the state of the
/// Bluetooth permission.
///
/// The view only flips stored switches and reads the permission; the question itself is asked by
/// the running module when it starts, never from here.
struct AccessoryAlertsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AccessoryAlertsSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Alert when an accessory connects", isOn: $settings.connect)
            caption(Text("A capsule below the notch names the accessory for five seconds."))
            Toggle("Alert when an accessory disconnects", isOn: $settings.disconnect)
            caption(Text("Off by default, because AirPods disconnect whenever they go back in their case."))
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
    }

    /// What macOS lets holzBar do with Bluetooth: the running module's last finding, or the
    /// system's answer while the module does not run.
    private var access: BluetoothAccess {
        appState.notchHub.runtime(AccessoryAlertsRuntime.self)?.access ?? BluetoothDeviceMonitor.access
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
