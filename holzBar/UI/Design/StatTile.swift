//
//  StatTile.swift
//  holzBar
//

import SwiftUI

/// A readout tile: a title, a large value with its unit and, if the value is a share of
/// something, a ring that fills and changes colour as it nears the limit.
struct StatTile: View {
    private let title: Text
    private let value: String
    private let unit: Text?
    private let fraction: Double?

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - title: What is measured.
    ///   - value: The value, already formatted.
    ///   - unit: The unit, if any.
    ///   - fraction: The share of the limit from 0 to 1, or `nil` for a value without a ring.
    init(title: Text, value: String, unit: Text? = nil, fraction: Double? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.fraction = fraction
    }

    private var levelColor: Color {
        switch GaugeLevel.level(for: fraction ?? 0) {
        case .normal: HolzBarTheme.Palette.success
        case .elevated: HolzBarTheme.Palette.warning
        case .critical: HolzBarTheme.Palette.danger
        }
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            if let fraction {
                ring(fraction)
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs / 2) {
                title
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.Spacing.xxs) {
                    Text(verbatim: value)
                        .font(HolzBarTheme.Typography.title)
                        .monospacedDigit()
                        .foregroundStyle(HolzBarTheme.Palette.text)
                    if let unit {
                        unit
                            .font(HolzBarTheme.Typography.callout)
                            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(HolzBarTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HolzBarTheme.Palette.groundElevated,
            in: HolzBarTheme.shape(HolzBarTheme.Radius.card)
        )
        .overlay {
            HolzBarTheme.shape(HolzBarTheme.Radius.card)
                .stroke(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: percentText))
    }

    private var percentText: String {
        guard let fraction, fraction.isFinite else {
            return value
        }
        let clamped = min(max(fraction, 0), 1)
        return "\(value), \(Int((clamped * 100).rounded())) %"
    }

    private func ring(_ fraction: Double) -> some View {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return ZStack {
            Circle()
                .stroke(HolzBarTheme.Palette.stroke, lineWidth: 5)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(levelColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: HolzBarTheme.Spacing.xxl + HolzBarTheme.Spacing.xs, height: HolzBarTheme.Spacing.xxl + HolzBarTheme.Spacing.xs)
        .accessibilityHidden(true)
    }
}

#Preview("StatTile") {
    VStack {
        StatTile(title: Text(verbatim: "CPU"), value: "59", unit: Text(verbatim: "%"), fraction: 0.59)
        StatTile(title: Text(verbatim: "Memory"), value: "12.5", unit: Text(verbatim: "GB"), fraction: 0.9)
        StatTile(title: Text(verbatim: "Uptime"), value: "3 d")
    }
    .padding()
    .frame(width: 280)
    .background(HolzBarTheme.Palette.ground)
}
