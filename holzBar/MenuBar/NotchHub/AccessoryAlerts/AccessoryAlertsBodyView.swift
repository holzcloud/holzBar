//
//  AccessoryAlertsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessories tab: the paired Bluetooth devices that are connected now, with the battery
/// level of those that report one.
///
/// A battery is joined to a device only when exactly one device and exactly one battery have
/// the same name, because the two lists share no identifier; every other battery is its own
/// row. When holzBar may not use Bluetooth and there is nothing to list, the tab says so and
/// offers the pane of System Settings. Names are shown as they are and never logged.
struct AccessoryAlertsBodyView: View {
    let runtime: AccessoryAlertsRuntime

    /// One line of the tab.
    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let percent: Int?
        /// Whether the Bluetooth monitor lists the device as connected; a battery-only row is not.
        let isConnected: Bool
    }

    /// Devices first, each with its battery when the join is unambiguous, then the batteries of
    /// accessories the monitor does not list.
    private var rows: [Row] {
        let devices = runtime.connected
        let batteries = runtime.batteries
        var joined = Set<String>()
        var result = [Row]()
        for device in devices {
            let sameNameDevices = devices.filter { $0.name == device.name }
            let sameNameBatteries = batteries.filter { $0.name == device.name }
            var percent: Int?
            if sameNameDevices.count == 1, sameNameBatteries.count == 1, let battery = sameNameBatteries.first {
                percent = battery.percent
                joined.insert(battery.id)
            }
            result.append(
                Row(id: device.id, symbol: device.symbolName, name: device.name, percent: percent, isConnected: true)
            )
        }
        for battery in batteries where !joined.contains(battery.id) {
            result.append(
                Row(
                    id: "battery:" + battery.id,
                    symbol: Self.symbol(for: battery),
                    name: battery.name,
                    percent: battery.percent,
                    isConnected: false
                )
            )
        }
        return result
    }

    private static func symbol(for battery: AccessoryBattery) -> String {
        switch battery.category {
        case "Keyboard": "keyboard"
        case "Mouse": "computermouse"
        default: "battery.25percent"
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        let rows = rows
        if runtime.access == .denied, rows.isEmpty {
            EmptyState(
                systemImage: "airpods",
                title: Text("Accessories"),
                message: Text("holzBar may not use Bluetooth, so connection alerts are off."),
                actionTitle: "Open Bluetooth Settings"
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
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

    private func row(_ row: Row) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: row.symbol)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                Text(verbatim: row.name)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                if row.percent == nil {
                    Text("Connected")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let percent = row.percent {
                // The number is always shown, so the level never relies on its colour alone.
                Text(verbatim: AccessoryBattery.percentText(percent))
                    .font(HolzBarTheme.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(levelColor(percent))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: row))
    }

    /// The colour of the level: the gauge levels read how empty the battery is.
    private func levelColor(_ percent: Int) -> Color {
        switch GaugeLevel.level(for: Double(100 - percent) / 100) {
        case .normal: HolzBarTheme.Palette.success
        case .elevated: HolzBarTheme.Palette.warning
        case .critical: HolzBarTheme.Palette.danger
        }
    }

    private func label(for row: Row) -> Text {
        switch (row.percent, row.isConnected) {
        case let (percent?, true):
            return Text("\(row.name), connected, battery \(percent) percent")
        case let (percent?, false):
            return Text("\(row.name), battery \(percent) percent")
        case (nil, _):
            return Text("\(row.name), connected")
        }
    }
}
