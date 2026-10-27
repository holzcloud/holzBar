//
//  HubRightWingView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's right wing: the status pills of the modules and the round settings button.
///
/// The wing is clipped to its rectangle, so a long pill never reaches the notch.
struct HubRightWingView: View {
    let model: NotchHubModel
    let host: any HubHost
    /// The width of the wing.
    let wingWidth: CGFloat
    /// The height of the top row.
    let rowHeight: CGFloat

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Spacer(minLength: 0)
            ForEach(model.pills, id: \.id) { entry in
                pill(entry.pill)
            }
            settingsButton
        }
        .frame(width: wingWidth, height: rowHeight)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private func pill(_ pill: HubStatusPill) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            if let symbol = pill.symbol {
                Image(systemName: symbol)
            }
            Text(verbatim: pill.text)
                .monospacedDigit()
        }
        .font(HolzBarTheme.Hub.pillFont)
        .foregroundStyle(HolzBarTheme.Hub.pillText)
        .lineLimit(1)
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .frame(height: HolzBarTheme.Hub.tabSize.height)
        .background(HolzBarTheme.Hub.pillFill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.accessibilityLabel)
    }

    private var settingsButton: some View {
        Button {
            host.openSettings(for: NotchHubController.moduleID)
        } label: {
            Image(systemName: "gearshape")
                .font(HolzBarTheme.Hub.tabSymbolFont)
                .foregroundStyle(HolzBarTheme.Hub.idleTabSymbol)
                .frame(width: HolzBarTheme.Hub.settingsButtonSize, height: HolzBarTheme.Hub.settingsButtonSize)
                .background(HolzBarTheme.Hub.idleTabFill, in: Circle())
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel(Text("Settings"))
    }
}
