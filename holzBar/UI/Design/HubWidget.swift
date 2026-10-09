//
//  HubWidget.swift
//  holzBar
//

import SwiftUI

/// A calm, small widget of the notch hub: a ring with the module's symbol, the name in small
/// capitals, the value and at most one quiet line. Four of them fit in a row.
///
/// The hub is always dark, so the widget uses fixed white tints instead of the theme's
/// adaptive colours.
struct HubWidget: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let systemImage: String
    private let title: Text
    private let value: String
    private let unit: Text?
    private let detail: Text?
    private let fraction: Double?

    /// Creates a widget.
    ///
    /// - Parameters:
    ///   - systemImage: The module's symbol, shown inside the ring.
    ///   - title: What is measured.
    ///   - value: The value, already formatted.
    ///   - unit: The unit, if any.
    ///   - detail: One quiet extra line, if any.
    ///   - fraction: The share of the limit from 0 to 1, or `nil` for a state without a level.
    init(
        systemImage: String,
        title: Text,
        value: String,
        unit: Text? = nil,
        detail: Text? = nil,
        fraction: Double? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.unit = unit
        self.detail = detail
        self.fraction = fraction
    }

    private var clampedFraction: Double? {
        fraction.map { $0.isFinite ? min(max($0, 0), 1) : 0 }
    }

    private var levelColor: Color {
        switch GaugeLevel.level(for: clampedFraction ?? 0) {
        case .normal: HolzBarTheme.Palette.success
        case .elevated: HolzBarTheme.Palette.warning
        case .critical: HolzBarTheme.Palette.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ring
            title
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let unit {
                    unit
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            if let detail {
                detail
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .white.opacity(reduceTransparency ? 0.1 : 0.045),
            in: HolzBarTheme.shape(14)
        )
        .overlay {
            HolzBarTheme.shape(14)
                .stroke(.white.opacity(0.06), lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let clampedFraction else {
            return value
        }
        return "\(value), \(Int((clampedFraction * 100).rounded())) %"
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 3)
            if let clampedFraction {
                Circle()
                    .trim(from: 0, to: clampedFraction)
                    .stroke(levelColor.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

#Preview("HubWidget") {
    HStack(spacing: 6) {
        HubWidget(systemImage: "cpu", title: Text(verbatim: "CPU"), value: "59", unit: Text(verbatim: "%"), fraction: 0.59)
        HubWidget(systemImage: "memorychip", title: Text(verbatim: "Memory"), value: "12.5", unit: Text(verbatim: "GB"), detail: Text(verbatim: "of 16 GB"), fraction: 0.78)
        HubWidget(systemImage: "battery.75", title: Text(verbatim: "Battery"), value: "92", unit: Text(verbatim: "%"), fraction: 0.92)
        HubWidget(systemImage: "wifi", title: Text(verbatim: "Network"), value: "Online")
    }
    .padding(14)
    .frame(width: 520)
    .background(Color(red: 0.04, green: 0.08, blue: 0.15))
}
