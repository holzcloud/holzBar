//
//  SettingsChoiceRows.swift
//  holzBar
//

import SwiftUI

/// A row with a pop-up button (D-18): as wide as its longest item, never wider than 260 pt. Beyond
/// that the pop-up keeps 260 pt and its title truncates (concept 12). Both forms draw through the
/// kit row, so the entry form hands `entry.id` to the chrome (reveal and highlight).
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    private let label: SettingsRowTitle
    private let selection: Binding<Value>
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let options: Options

    init(
        _ entry: SettingsEntry,
        selection: Binding<Value>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder options: () -> Options
    ) {
        label = SettingsRowTitle(entry)
        self.selection = selection
        self.small = small
        self.badge = badge
        self.info = info
        self.options = options()
    }

    init(
        _ title: Text,
        selection: Binding<Value>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder options: () -> Options
    ) {
        label = SettingsRowTitle(title)
        self.selection = selection
        self.small = small
        self.badge = badge
        self.info = info
        self.options = options()
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            ViewThatFits(in: .horizontal) {
                picker.fixedSize()
                picker.frame(width: HolzBarTheme.SettingsKit.popUpMaxWidth)
            }
            .frame(maxWidth: HolzBarTheme.SettingsKit.popUpMaxWidth, alignment: .trailing)
        }
    }

    private var picker: some View {
        Picker(selection: selection) {
            options
        } label: {
            label.title
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

/// A row with a segmented control of two to four short options (D-18).
struct SettingsSegmentedRow<Value: Hashable, Options: View>: View {
    private let label: SettingsRowTitle
    private let selection: Binding<Value>
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let options: Options

    init(
        _ entry: SettingsEntry,
        selection: Binding<Value>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder options: () -> Options
    ) {
        label = SettingsRowTitle(entry)
        self.selection = selection
        self.small = small
        self.badge = badge
        self.info = info
        self.options = options()
    }

    init(
        _ title: Text,
        selection: Binding<Value>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder options: () -> Options
    ) {
        label = SettingsRowTitle(title)
        self.selection = selection
        self.small = small
        self.badge = badge
        self.info = info
        self.options = options()
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            Picker(selection: selection) {
                options
            } label: {
                label.title
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// A row with a segmented control of which any number can be selected, such as the weekdays
/// (D-18). macOS draws a `ControlGroup` of button-style toggles as one segmented control.
struct SettingsMultiSegmentedRow<Value: Hashable>: View {
    private let label: SettingsRowTitle
    private let selection: Binding<Set<Value>>
    private let values: [Value]
    private let info: Text?
    private let name: (Value) -> Text

    init(
        _ entry: SettingsEntry,
        selection: Binding<Set<Value>>,
        values: [Value],
        info: Text? = nil,
        name: @escaping (Value) -> Text
    ) {
        label = SettingsRowTitle(entry)
        self.selection = selection
        self.values = values
        self.info = info
        self.name = name
    }

    init(
        _ title: Text,
        selection: Binding<Set<Value>>,
        values: [Value],
        info: Text? = nil,
        name: @escaping (Value) -> Text
    ) {
        label = SettingsRowTitle(title)
        self.selection = selection
        self.values = values
        self.info = info
        self.name = name
    }

    var body: some View {
        SettingsRow(label, info: info) {
            ControlGroup {
                ForEach(values, id: \.self) { value in
                    Toggle(isOn: binding(for: value)) {
                        name(value)
                    }
                    .toggleStyle(.button)
                }
            } label: {
                label.title
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func binding(for value: Value) -> Binding<Bool> {
        Binding {
            selection.wrappedValue.contains(value)
        } set: { isOn in
            if isOn {
                selection.wrappedValue.insert(value)
            } else {
                selection.wrappedValue.remove(value)
            }
        }
    }
}
