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
    @Environment(\.colorSchemeContrast) private var contrast

    private let systemImage: String
    private let title: Text
    private let value: String
    private let unit: Text?
    private let detail: Text?
    private let fraction: Double?
    private let level: GaugeLevel?
    private let stateLine: HubTileStateLine?
    private let accessibilityText: Text?
    private let help: Text?

    /// Creates a widget.
    ///
    /// - Parameters:
    ///   - systemImage: The module's symbol, shown inside the ring.
    ///   - title: What is measured.
    ///   - value: The value, already formatted.
    ///   - unit: The unit, if any.
    ///   - detail: One quiet extra line, if any.
    ///   - fraction: The share of the limit from 0 to 1, or `nil` for a state without a level.
    ///   - level: The ring's colour, when the caller decides it; the ring follows the fraction
    ///     otherwise.
    ///   - stateLine: A state shown in place of the quiet line, in its own colour.
    ///   - accessibilityValue: What VoiceOver reads as the value. With it the widget is one
    ///     element named by the title; without it the texts are read combined.
    ///   - help: The tooltip.
    init(
        systemImage: String,
        title: Text,
        value: String,
        unit: Text? = nil,
        detail: Text? = nil,
        fraction: Double? = nil,
        level: GaugeLevel? = nil,
        stateLine: HubTileStateLine? = nil,
        accessibilityValue: Text? = nil,
        help: Text? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.unit = unit
        self.detail = detail
        self.fraction = fraction
        self.level = level
        self.stateLine = stateLine
        self.accessibilityText = accessibilityValue
        self.help = help
    }

    private var clampedFraction: Double? {
        fraction.map { $0.isFinite ? min(max($0, 0), 1) : 0 }
    }

    /// The name and the quiet line are stronger under Increase Contrast.
    private var labelAlpha: Double {
        contrast == .increased ? DesignTokens.Hub.tileLabelAlphaIncreased : DesignTokens.Hub.tileLabelAlpha
    }

    private var detailAlpha: Double {
        contrast == .increased ? DesignTokens.Hub.tileDetailAlphaIncreased : DesignTokens.Hub.tileDetailAlpha
    }

    private var levelColor: Color {
        switch level ?? GaugeLevel.level(for: clampedFraction ?? 0) {
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
                .foregroundStyle(.white.opacity(labelAlpha))
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
            if let stateLine {
                HStack(spacing: 4) {
                    Image(systemName: stateLine.symbol)
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                    stateLine.text
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(stateLine.tint.color)
            } else if let detail {
                detail
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(detailAlpha))
                    .lineLimit(1)
            }
        }
        .padding(CGFloat(DesignTokens.Hub.tilePadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .white.opacity(reduceTransparency ? DesignTokens.Hub.tileFillAlphaOpaque : DesignTokens.Hub.tileFillAlpha),
            in: HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
        )
        .overlay {
            HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
                .stroke(.white.opacity(0.06), lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .modifier(HubWidgetAccessibility(title: title, value: accessibilityText, spokenValue: spokenValue))
        .modifier(HubWidgetHelp(help: help))
    }

    private var spokenValue: String {
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

extension HubWidget {
    /// Creates the widget of a module's tile.
    init(tile: HubTile) {
        self.init(
            systemImage: tile.symbol,
            title: tile.title,
            value: tile.value,
            unit: tile.unit,
            detail: tile.detail,
            fraction: tile.fraction,
            level: tile.level,
            stateLine: tile.stateLine,
            accessibilityValue: tile.accessibilityValue,
            help: tile.help
        )
    }
}

/// A tile with a spoken value is one element: the title is its label and the value is what the
/// caller wrote. Other tiles read their texts combined, with the ring's share after the value.
private struct HubWidgetAccessibility: ViewModifier {
    let title: Text
    let value: Text?
    let spokenValue: String

    func body(content: Content) -> some View {
        if let value {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(verbatim: spokenValue))
        }
    }
}

/// The tooltip of a tile, when it has one.
private struct HubWidgetHelp: ViewModifier {
    let help: Text?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
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
