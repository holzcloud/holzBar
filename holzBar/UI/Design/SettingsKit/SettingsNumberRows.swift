//
//  SettingsNumberRows.swift
//  holzBar
//

import SwiftUI

/// A row with a slider and its value (D-18): a 120 pt track, then the value right-aligned in
/// monospaced digits at least 34 pt wide. The pane passes the value text with its unit. A stored
/// value outside the range is shown clamped and written only when the user moves the slider.
struct SettingsSliderRow: View {
    private let label: SettingsRowTitle
    private let value: Binding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let valueLabel: (Double) -> Text

    init(
        _ entry: SettingsEntry,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        valueLabel: @escaping (Double) -> Text
    ) {
        label = SettingsRowTitle(entry)
        self.value = value
        self.range = range
        self.step = step
        self.small = small
        self.badge = badge
        self.info = info
        self.valueLabel = valueLabel
    }

    init(
        _ title: Text,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        valueLabel: @escaping (Double) -> Text
    ) {
        label = SettingsRowTitle(title)
        self.value = value
        self.range = range
        self.step = step
        self.small = small
        self.badge = badge
        self.info = info
        self.valueLabel = valueLabel
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            HStack(spacing: HolzBarTheme.SettingsKit.sliderValueGap) {
                Slider(value: clamped, in: range, step: step) {
                    label.title
                }
                .labelsHidden()
                .frame(width: HolzBarTheme.SettingsKit.sliderTrackWidth)
                .accessibilityValue(valueLabel(shown))
                valueLabel(shown)
                    .font(HolzBarTheme.Typography.callout)
                    .monospacedDigit()
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .frame(minWidth: HolzBarTheme.SettingsKit.sliderValueMinWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var shown: Double {
        min(max(value.wrappedValue, range.lowerBound), range.upperBound)
    }

    private var clamped: Binding<Double> {
        Binding {
            shown
        } set: { newValue in
            value.wrappedValue = newValue
        }
    }
}

/// A row with a stepper and its value 6 pt before it (D-18). `step` lets a pane move in larger
/// steps, such as battery levels by 5.
struct SettingsStepperRow: View {
    private let label: SettingsRowTitle
    private let value: Binding<Int>
    private let range: ClosedRange<Int>
    private let step: Int
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let valueLabel: (Int) -> Text

    init(
        _ entry: SettingsEntry,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        valueLabel: @escaping (Int) -> Text
    ) {
        label = SettingsRowTitle(entry)
        self.value = value
        self.range = range
        self.step = step
        self.small = small
        self.badge = badge
        self.info = info
        self.valueLabel = valueLabel
    }

    init(
        _ title: Text,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        valueLabel: @escaping (Int) -> Text
    ) {
        label = SettingsRowTitle(title)
        self.value = value
        self.range = range
        self.step = step
        self.small = small
        self.badge = badge
        self.info = info
        self.valueLabel = valueLabel
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            HStack(spacing: HolzBarTheme.SettingsKit.stepperValueGap) {
                valueLabel(value.wrappedValue)
                    .font(HolzBarTheme.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .accessibilityHidden(true)
                Stepper(value: value, in: range, step: step) {
                    label.title
                }
                .labelsHidden()
                .accessibilityValue(valueLabel(value.wrappedValue))
            }
        }
    }
}
