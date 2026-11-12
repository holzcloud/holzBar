//
//  SettingsRow.swift
//  holzBar
//

import SwiftUI

/// The badge after the small text of a row, before its info button (D-17). The kit only offers
/// the two badges that exist; their looks do not change.
enum SettingsBadge {
    case preview
    case beta
}

/// Shows the badge of a row and nothing else.
struct SettingsBadgeView: View {
    private let badge: SettingsBadge

    init(_ badge: SettingsBadge) {
        self.badge = badge
    }

    var body: some View {
        switch badge {
        case .preview:
            PreviewBadge()
        case .beta:
            BetaBadge()
        }
    }
}

/// The label source both forms of a row resolve to: the entry form takes the label, the id and
/// the info text from the catalogue entry, the text form only a title (D-17).
struct SettingsRowTitle {
    let title: Text
    let entryID: String?
    let info: Text?

    init(_ entry: SettingsEntry) {
        title = Text(entry.label)
        entryID = entry.id
        info = entry.info.map { Text($0) }
    }

    init(_ title: Text) {
        self.title = title
        entryID = nil
        info = nil
    }
}

/// The leading part of a row (D-09, D-17, D-22): the label, which wraps, then the small text,
/// the badge and the info button with 6 pt gaps.
struct SettingsLabelColumn: View {
    let title: Text
    let small: Text?
    let badge: SettingsBadge?
    let info: Text?

    @Environment(\.settingsParentIsOn) private var parentIsOn

    var body: some View {
        HStack(alignment: .center, spacing: HolzBarTheme.SettingsKit.accessoryGap) {
            HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                title
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(SettingsUnavailableValue(isUnavailable: !parentIsOn))
                if let small {
                    small
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .fixedSize()
                }
            }
            if let badge {
                SettingsBadgeView(badge)
                    .fixedSize()
            }
            if let info {
                SettingsInfoButton(info)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Texts the kit owns, so that one source serves every row variant.
enum SettingsKitText {
    /// What VoiceOver reads with a row that is dimmed because its parent switch is off (D-17);
    /// no position words.
    static var unavailable: Text {
        Text("Not available with the current settings.")
    }
}

/// Gives a dimmed row's label the value "Not available with the current settings." (D-17).
struct SettingsUnavailableValue: ViewModifier {
    let isUnavailable: Bool

    func body(content: Content) -> some View {
        if isUnavailable {
            content.accessibilityValue(SettingsKitText.unavailable)
        } else {
            content
        }
    }
}

/// The hint of a row's control: the info text, when there is one (D-22).
private struct SettingsInfoHint: ViewModifier {
    let info: Text?

    func body(content: Content) -> some View {
        if let info {
            content.accessibilityHint(info)
        } else {
            content
        }
    }
}

/// One row of a settings group (D-01, D-17): the label column at the leading edge and the
/// control at the trailing edge, at least 16 pt apart. While the parent switch is off (D-17) the
/// row is dimmed before the chrome, so its hairline keeps full strength, and only the control is
/// disabled, so the info button keeps working. The control sizes itself; a text field
/// stays flexible. The entry form takes label and info from the catalogue; the text form is for
/// labels that are user data or repeat per item.
struct SettingsRow<Control: View>: View {
    private let label: SettingsRowTitle
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let control: Control

    @Environment(\.settingsParentIsOn) private var parentIsOn

    /// A row whose label and info text come from a catalogue entry. An `info` passed here
    /// replaces the popover text only (a per-state explanation); the entry's info stays the
    /// search text.
    init(
        _ entry: SettingsEntry,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.init(SettingsRowTitle(entry), small: small, badge: badge, info: info, control: control)
    }

    /// A row with a title that is user data or repeats per item.
    init(
        _ title: Text,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.init(SettingsRowTitle(title), small: small, badge: badge, info: info, control: control)
    }

    init(
        _ label: SettingsRowTitle,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.small = small
        self.badge = badge
        self.info = info
        self.control = control()
    }

    var body: some View {
        let popoverText = info ?? label.info
        HStack(alignment: .center, spacing: HolzBarTheme.SettingsKit.labelControlGap) {
            SettingsLabelColumn(title: label.title, small: small, badge: badge, info: popoverText)
            control
                .layoutPriority(1)
                .modifier(SettingsInfoHint(info: popoverText))
                .disabled(!parentIsOn)
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome(entryID: label.entryID)
        .accessibilityElement(children: .contain)
    }
}
