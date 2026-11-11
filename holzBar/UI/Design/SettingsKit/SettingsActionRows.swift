//
//  SettingsActionRows.swift
//  holzBar
//

import SwiftUI

/// The button style of a button row (D-18): the system push button, with the title of a
/// destructive button in `danger`. A button a pane styles itself (the one primary,
/// `.borderedProminent`) keeps its own style, because the nearer style wins. Confirmations stay
/// with the panes (D-10); the kit adds no action of its own.
struct SettingsPushButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if configuration.role == .destructive {
            Button(configuration)
                .buttonStyle(.automatic)
                .foregroundStyle(HolzBarTheme.Palette.danger)
        } else {
            Button(configuration)
                .buttonStyle(.automatic)
        }
    }
}

/// A row of one or more buttons at the trailing edge (D-18). The label may be empty (a row that
/// holds only buttons) or absent from the screen (the unlabeled entry form, whose label is only
/// the VoiceOver name and the search text). At most one primary button per group is a pane rule
/// (`.borderedProminent`, set by the pane); the kit does not count.
struct SettingsButtonRow<Buttons: View>: View {
    private let label: SettingsRowTitle?
    private let entryID: String?
    private let accessibilityName: Text?
    private let unlabeledInfo: Text?
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?
    private let buttons: Buttons

    @Environment(\.settingsParentIsOn) private var parentIsOn

    /// A row whose label and info text come from a catalogue entry.
    init(
        _ entry: SettingsEntry,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder buttons: () -> Buttons
    ) {
        label = SettingsRowTitle(entry)
        entryID = entry.id
        accessibilityName = nil
        unlabeledInfo = nil
        self.small = small
        self.badge = badge
        self.info = info
        self.buttons = buttons()
    }

    /// A row with a title that is user data or repeats per item.
    init(
        _ title: Text,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil,
        @ViewBuilder buttons: () -> Buttons
    ) {
        label = SettingsRowTitle(title)
        entryID = nil
        accessibilityName = nil
        unlabeledInfo = nil
        self.small = small
        self.badge = badge
        self.info = info
        self.buttons = buttons()
    }

    /// A row that shows no label, only the info button and the buttons ("Add rule…",
    /// "Choose Folder…"). The entry still gives the row its id for the search and its name for
    /// VoiceOver.
    init(
        unlabeled entry: SettingsEntry,
        info: Text? = nil,
        @ViewBuilder buttons: () -> Buttons
    ) {
        label = nil
        entryID = entry.id
        accessibilityName = Text(entry.label)
        unlabeledInfo = info ?? entry.info.map { Text($0) }
        small = nil
        badge = nil
        self.info = nil
        self.buttons = buttons()
    }

    /// A row of buttons with an empty label and no entry.
    init(@ViewBuilder buttons: () -> Buttons) {
        label = nil
        entryID = nil
        accessibilityName = nil
        unlabeledInfo = nil
        small = nil
        badge = nil
        info = nil
        self.buttons = buttons()
    }

    var body: some View {
        if let label {
            SettingsRow(label, small: small, badge: badge, info: info) {
                buttonStack
            }
        } else {
            unlabeledRow
        }
    }

    private var buttonStack: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            buttons
        }
        .buttonStyle(SettingsPushButtonStyle())
        .fixedSize()
    }

    private var unlabeledRow: some View {
        HStack(alignment: .center, spacing: HolzBarTheme.SettingsKit.labelControlGap) {
            if let unlabeledInfo {
                SettingsInfoButton(unlabeledInfo)
            }
            Spacer(minLength: HolzBarTheme.SettingsKit.labelControlGap)
            buttonStack
                .modifier(SettingsButtonHint(hint: unlabeledInfo))
                .disabled(!parentIsOn)
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome(entryID: entryID)
        .accessibilityElement(children: .contain)
        .modifier(SettingsButtonName(name: accessibilityName))
    }
}

/// The info text as the VoiceOver hint of a button row's buttons (D-22).
private struct SettingsButtonHint: ViewModifier {
    let hint: Text?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// The entry's label as the VoiceOver name of an unlabeled button row.
private struct SettingsButtonName: ViewModifier {
    let name: Text?

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityLabel(name)
        } else {
            content
        }
    }
}

/// A row with a hotkey recorder (D-18): 132 x 24, "Record" in `textTertiary` while empty. The
/// text form serves per-item and per-profile hotkeys.
struct SettingsHotkeyRow: View {
    private let label: SettingsRowTitle
    private let hotkey: Hotkey
    private let settings: HotkeysSettings
    private let small: Text?
    private let badge: SettingsBadge?
    private let info: Text?

    init(
        _ entry: SettingsEntry,
        hotkey: Hotkey,
        settings: HotkeysSettings,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(entry)
        self.hotkey = hotkey
        self.settings = settings
        self.small = small
        self.badge = badge
        self.info = info
    }

    init(
        _ title: Text,
        hotkey: Hotkey,
        settings: HotkeysSettings,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        info: Text? = nil
    ) {
        label = SettingsRowTitle(title)
        self.hotkey = hotkey
        self.settings = settings
        self.small = small
        self.badge = badge
        self.info = info
    }

    var body: some View {
        SettingsRow(label, small: small, badge: badge, info: info) {
            HotkeyRecorder(hotkey: hotkey, settings: settings) {
                label.title
            }
            .labelsHidden()
        }
    }
}
