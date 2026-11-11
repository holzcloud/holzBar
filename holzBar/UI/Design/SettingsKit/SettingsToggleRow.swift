//
//  SettingsToggleRow.swift
//  holzBar
//

import SwiftUI

/// The one switch of the Settings window (D-24): a mini switch in the accent colour with a hit
/// area of at least 24 pt. The label stays the VoiceOver label; the switch shows none.
struct SettingsSwitch: View {
    @Binding private var isOn: Bool
    private let label: Text

    init(isOn: Binding<Bool>, label: Text) {
        _isOn = isOn
        self.label = label
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(HolzBarTheme.Palette.accent)
        .fixedSize()
        .frame(minHeight: HolzBarTheme.SettingsKit.switchMinHeight)
    }
}

/// A row with the one mini switch at its trailing edge (D-17, D-18, D-24). The entry form takes
/// label and info from the catalogue; the text form is for labels that are user data or repeat
/// per item.
struct SettingsToggleRow: View {
    private let label: SettingsRowTitle
    @Binding private var isOn: Bool
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?

    init(
        _ entry: SettingsEntry,
        isOn: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(entry)
        _isOn = isOn
        self.small = small
        self.badge = badge
        self.info = info
    }

    init(
        _ title: Text,
        isOn: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(title)
        _isOn = isOn
        self.small = small
        self.badge = badge
        self.info = info
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            SettingsSwitch(isOn: $isOn, label: label.title)
        }
    }
}
