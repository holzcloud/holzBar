//
//  SettingsColorRows.swift
//  holzBar
//

import SwiftUI

/// A row with a colour well (D-18): the system colour picker, shaped by the kit to 40 x 20 with
/// radius 6 and a 1 pt stroke in the kit's hairline colour. The order is fixed so that the stroke
/// lies on the clipped edge.
struct SettingsColorRow: View {
    private let label: SettingsRowTitle
    private let color: Binding<CGColor>
    private let supportsOpacity: Bool
    private let info: Text?

    init(
        _ entry: SettingsEntry,
        color: Binding<CGColor>,
        supportsOpacity: Bool = false,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(entry)
        self.color = color
        self.supportsOpacity = supportsOpacity
        self.info = info
    }

    init(
        _ title: Text,
        color: Binding<CGColor>,
        supportsOpacity: Bool = false,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(title)
        self.color = color
        self.supportsOpacity = supportsOpacity
        self.info = info
    }

    var body: some View {
        SettingsRow(label, info: info) {
            ColorPicker(selection: color, supportsOpacity: supportsOpacity) {
                label.title
            }
            .labelsHidden()
            .frame(
                width: HolzBarTheme.SettingsKit.colorWellWidth,
                height: HolzBarTheme.SettingsKit.colorWellHeight
            )
            .clipShape(HolzBarTheme.shape(HolzBarTheme.SettingsKit.colorWellRadius))
            .overlay {
                HolzBarTheme.shape(HolzBarTheme.SettingsKit.colorWellRadius)
                    .strokeBorder(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A row with a gradient strip (D-18): the gradient picker, 96 pt wide. The strip is 20 pt high
/// inside the picker's 24 pt frame and keeps the picker's own shape and border.
struct SettingsGradientRow: View {
    private let label: SettingsRowTitle
    private let gradient: Binding<HolzBarGradient>
    private let supportsOpacity: Bool
    private let info: Text?

    init(
        _ entry: SettingsEntry,
        gradient: Binding<HolzBarGradient>,
        supportsOpacity: Bool = false,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(entry)
        self.gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.info = info
    }

    var body: some View {
        SettingsRow(label, info: info) {
            HolzBarGradientPicker(
                gradient: gradient,
                supportsOpacity: supportsOpacity,
                stripWidth: HolzBarTheme.SettingsKit.gradientStripWidth
            )
        }
    }
}
