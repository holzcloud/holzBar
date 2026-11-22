//
//  AccessoryAlertsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessories tab: the connected devices with their battery level where they report one,
/// then the paired devices that are not connected, in grey.
///
/// The rows come from ``ConnectedDeviceList`` through the devices service, the same rule as the
/// Devices list in Settings: one row per device name, a device with several battery parts at its
/// lowest part. When holzBar may not use Bluetooth and there is nothing to list, the tab says so
/// and offers the pane of System Settings. Names are shown as they are and never logged.
struct AccessoryAlertsBodyView: View {
    let runtime: AccessoryAlertsRuntime

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                runtime.devicesListDidAppear()
            }
            .onDisappear {
                runtime.devicesListDidDisappear()
            }
    }

    @ViewBuilder
    private var content: some View {
        let rows = runtime.deviceRows
        if runtime.access == .denied, rows.isEmpty {
            EmptyState(
                systemImage: "airpods",
                title: Text("Accessories"),
                message: Text("holzBar may not use Bluetooth, so connection alerts are off."),
                actionTitle: "Open Bluetooth Settings",
                isCompact: true
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                if rows.isEmpty {
                    Text("No accessories connected")
                        .font(HolzBarTheme.Typography.callout)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                            ForEach(rows) { row in
                                self.row(row)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, HolzBarTheme.Spacing.xxs)
                    }
                }
                if runtime.batteryReadingUnavailable {
                    Text("Battery levels are not available on this version of macOS.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            }
        }
    }

    private func row(_ row: ConnectedDeviceRow) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: row.symbol)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(row.isConnected ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textTertiary)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            Text(verbatim: row.name)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(row.isConnected ? HolzBarTheme.Palette.text : HolzBarTheme.Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // The number is always shown, so the level never relies on its colour alone.
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

    /// A normal level is plain text; below 30 % it is `warning` and below 15 % `danger`. A paired
    /// device that is not connected is grey.
    private func valueColor(_ row: ConnectedDeviceRow) -> Color {
        guard row.isConnected else {
            return HolzBarTheme.Palette.textTertiary
        }
        switch row.level {
        case .critical: return HolzBarTheme.Palette.danger
        case .elevated: return HolzBarTheme.Palette.warning
        case .normal, nil: return HolzBarTheme.Palette.text
        }
    }
}
