//
//  AccessoryAlertsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessory alerts module's settings, in the open area of the module's row: the Devices
/// list (the connected devices with their levels, then the paired ones that are not connected),
/// a switch for connect alerts and one for disconnect alerts, the three settings of the battery
/// half (reading levels, labelled as a private interface, the low-battery alert and its level as
/// dependent sub rows), and the state of the Bluetooth permission.
///
/// The view only flips stored values and reads states; it never asks for the Bluetooth
/// permission, which only the running module does when it starts, and whether battery reading
/// switched itself off comes from the running module too. The Devices list registers as a
/// consumer of the connected-devices service while it is on screen and is gone with it. A change
/// of a battery setting tells the running module and the service, which read again.
struct AccessoryAlertsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AccessoryAlertsSettings()

    /// The name this list registers under with the connected-devices service.
    private static let consumer = "settings-devices"

    var body: some View {
        // A container only so that the change handlers run once.
        VStack(alignment: .leading, spacing: 0) {
            SettingsValueRow(.modulesAccessoryAlertsDevices, value: devicesValue, badge: .preview)
            devicesRows
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
        .onAppear {
            appState.connectedDevices.begin(Self.consumer, wantsDevices: true)
        }
        .onDisappear {
            appState.connectedDevices.end(Self.consumer)
        }
        .onChange(of: settings.readsBattery) {
            runtime?.settingsDidChange()
            appState.connectedDevices.batterySwitchDidChange()
        }
        .onChange(of: settings.lowBattery) {
            runtime?.settingsDidChange()
        }
        .onChange(of: settings.lowBatteryLevel) {
            runtime?.settingsDidChange()
        }
    }

    private var devices: ConnectedDevicesService {
        appState.connectedDevices
    }

    /// How many devices are connected, "None connected", or "Not available" while Bluetooth is
    /// denied and there is nothing to list.
    private var devicesValue: Text {
        let count = devices.rows.filter(\.isConnected).count
        if count > 0 {
            return Text("\(count) connected")
        }
        return access == .denied ? Text("Not available") : Text("None connected")
    }

    /// One sub row per device, or the empty state. Without the Bluetooth permission and without
    /// a level the state line below says why, so no empty row is drawn.
    @ViewBuilder
    private var devicesRows: some View {
        let rows = devices.rows
        if rows.isEmpty {
            if access != .denied {
                SettingsEmptyRow(
                    systemImage: "airpods",
                    Text("No accessories connected"),
                    caption: Text("Pair a device in System Settings > Bluetooth to see it here.")
                )
                .settingsSubRow()
            }
        } else {
            ForEach(rows) { row in
                SettingsBlockRow {
                    deviceRow(row)
                }
                .settingsSubRow()
            }
        }
    }

    private func deviceRow(_ row: ConnectedDeviceRow) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Image(systemName: row.symbol)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(row.isConnected ? HolzBarTheme.Palette.textSecondary : HolzBarTheme.Palette.textTertiary)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            Text(verbatim: row.name)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(row.isConnected ? HolzBarTheme.Palette.text : HolzBarTheme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            row.valueText
                .font(HolzBarTheme.Typography.body)
                .monospacedDigit()
                .foregroundStyle(valueColor(row))
        }
        .help(row.partsHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityValue(row.spokenParts ?? Text(verbatim: ""))
    }

    /// The level's colour is a state, never the only carrier: the number is always shown.
    private func valueColor(_ row: ConnectedDeviceRow) -> Color {
        guard row.isConnected else {
            return HolzBarTheme.Palette.textTertiary
        }
        switch row.level {
        case .critical: return HolzBarTheme.Palette.danger
        case .elevated: return HolzBarTheme.Palette.warning
        case .normal, nil: return HolzBarTheme.Palette.textSecondary
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

    /// What macOS lets holzBar do with Bluetooth, as the devices service last read it without
    /// asking anything.
    private var access: BluetoothAccess {
        devices.access
    }
}
