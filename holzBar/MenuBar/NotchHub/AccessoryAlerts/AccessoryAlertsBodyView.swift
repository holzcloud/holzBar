//
//  AccessoryAlertsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Accessories tab: the paired Bluetooth devices that are connected now.
///
/// When holzBar may not use Bluetooth the tab says so and offers the pane of System Settings.
/// Names are shown as they are and never logged.
struct AccessoryAlertsBodyView: View {
    let runtime: AccessoryAlertsRuntime

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        if runtime.access == .denied {
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
        } else if runtime.connected.isEmpty {
            Text("No accessories connected")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                    ForEach(runtime.connected) { device in
                        row(device)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, HolzBarTheme.Spacing.xxs)
            }
        }
    }

    private func row(_ device: AccessoryDevice) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: device.symbolName)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                Text(verbatim: device.name)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                Text("Connected")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(device.name), connected"))
    }
}
