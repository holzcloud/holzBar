//
//  SettingsValueRows.swift
//  holzBar
//

import SwiftUI

/// A row that shows a value instead of a control (D-18): the value in body size and
/// `textSecondary`, wrapping, and selectable so that a path or a command can be copied.
struct SettingsValueRow: View {
    private let label: SettingsRowTitle
    private let value: Text
    private let info: Text?

    init(_ entry: SettingsEntry, value: Text, info: Text? = nil) {
        label = SettingsRowTitle(entry)
        self.value = value
        self.info = info
    }

    init(_ title: Text, value: Text, info: Text? = nil) {
        label = SettingsRowTitle(title)
        self.value = value
        self.info = info
    }

    var body: some View {
        SettingsRow(label, info: info) {
            value
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// A row with a text field (D-18): at least 150 pt wide and no wider than a pop-up, so that rows
/// line up.
struct SettingsTextFieldRow: View {
    private let label: SettingsRowTitle
    private let text: Binding<String>
    private let prompt: Text?
    private let info: Text?

    init(_ entry: SettingsEntry, text: Binding<String>, prompt: Text? = nil, info: Text? = nil) {
        label = SettingsRowTitle(entry)
        self.text = text
        self.prompt = prompt
        self.info = info
    }

    init(_ title: Text, text: Binding<String>, prompt: Text? = nil, info: Text? = nil) {
        label = SettingsRowTitle(title)
        self.text = text
        self.prompt = prompt
        self.info = info
    }

    var body: some View {
        SettingsRow(label, info: info) {
            TextField(text: text, prompt: prompt) {
                label.title
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(
                minWidth: HolzBarTheme.SettingsKit.textFieldMinWidth,
                maxWidth: HolzBarTheme.SettingsKit.popUpMaxWidth
            )
        }
    }
}
