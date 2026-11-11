//
//  SettingsModuleRow.swift
//  holzBar
//

import SwiftUI

/// A module row (D-21, D-24): a 24 pt accent tile, the title in body medium with the badge, the
/// info button and the small text, a chevron button that opens the module's settings under the
/// row, and the one mini switch. The open area has the 7 or 8 % fill and indents the rows inside
/// to 46 pt. The row opens only through its `isOpen` binding, so the caller decides that one
/// module is open at a time. While the row is dependent and off, the switch is disabled and the
/// header dims; the chevron stays usable, because it only shows rows (D-27).
struct SettingsModuleRow<Settings: View>: View {
    private let label: SettingsRowTitle
    private let summary: Text?
    private let systemImage: String
    @Binding private var isOn: Bool
    private let isOpen: Binding<Bool>?
    private let small: Text?
    private let badge: SettingsBadge?
    private let settings: Settings?

    @Environment(\.settingsRowLeadingPadding) private var leadingPadding
    @Environment(\.settingsParentIsOn) private var parentIsOn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A module row whose title and summary come from a catalogue entry (the summary is the info
    /// text, falling back to the entry's info).
    init(
        _ entry: SettingsEntry,
        systemImage: String,
        isOn: Binding<Bool>,
        isOpen: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        @ViewBuilder settings: () -> Settings
    ) {
        label = SettingsRowTitle(entry)
        summary = (entry.summary ?? entry.info).map { Text($0) }
        self.systemImage = systemImage
        _isOn = isOn
        self.isOpen = isOpen
        self.small = small
        self.badge = badge
        self.settings = settings()
    }

    /// A module row for a rule row: the title and the summary are user data.
    init(
        _ title: Text,
        summary: Text?,
        systemImage: String,
        isOn: Binding<Bool>,
        isOpen: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil,
        @ViewBuilder settings: () -> Settings
    ) {
        label = SettingsRowTitle(title)
        self.summary = summary
        self.systemImage = systemImage
        _isOn = isOn
        self.isOpen = isOpen
        self.small = small
        self.badge = badge
        self.settings = settings()
    }

    fileprivate init(
        label: SettingsRowTitle,
        summary: Text?,
        systemImage: String,
        isOn: Binding<Bool>,
        small: Text?,
        badge: SettingsBadge?
    ) {
        self.label = label
        self.summary = summary
        self.systemImage = systemImage
        _isOn = isOn
        isOpen = nil
        self.small = small
        self.badge = badge
        settings = nil
    }

    private var isShowingSettings: Bool {
        isOpen?.wrappedValue ?? false
    }

    private var accentFill: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.accentFillDark
            : HolzBarTheme.SettingsKit.accentFillLight
    }

    private var openAreaFill: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.openAreaFillDark
            : HolzBarTheme.SettingsKit.openAreaFillLight
    }

    private var tile: some View {
        Image(systemName: systemImage)
            .font(.system(size: HolzBarTheme.SettingsKit.moduleSymbolSize))
            .foregroundStyle(HolzBarTheme.Palette.accent)
            .frame(
                width: HolzBarTheme.SettingsKit.moduleTileSize,
                height: HolzBarTheme.SettingsKit.moduleTileSize
            )
            .background(
                HolzBarTheme.Palette.accent.opacity(accentFill),
                in: HolzBarTheme.shape(HolzBarTheme.SettingsKit.moduleTileRadius)
            )
            .accessibilityHidden(true)
    }

    private func chevronButton(_ isOpen: Binding<Bool>) -> some View {
        Button {
            withAnimation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion)) {
                isOpen.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                .font(.system(size: HolzBarTheme.SettingsKit.moduleChevronSize, weight: .semibold))
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(
                    width: HolzBarTheme.SettingsKit.moduleChevronButtonSize,
                    height: HolzBarTheme.SettingsKit.moduleChevronButtonSize
                )
                .frame(
                    width: HolzBarTheme.SettingsKit.infoButtonHitArea,
                    height: HolzBarTheme.SettingsKit.infoButtonHitArea
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings"))
        .accessibilityValue(isOpen.wrappedValue ? Text("Expanded") : Text("Collapsed"))
        .help(Text("Settings"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HolzBarTheme.SettingsKit.moduleRowGap) {
            tile
            HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                label.title
                    .font(HolzBarTheme.Typography.body.weight(.medium))
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(SettingsUnavailableValue(isUnavailable: !parentIsOn))
                if let badge {
                    SettingsBadgeView(badge).fixedSize()
                }
                if let summary {
                    SettingsInfoButton(summary)
                }
                if let small {
                    small
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let isOpen {
                chevronButton(isOpen)
            }
            SettingsSwitch(isOn: $isOn, label: label.title)
                .modifier(SettingsModuleHint(summary: summary))
                .disabled(!parentIsOn)
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome(entryID: label.entryID, minHeight: HolzBarTheme.SettingsKit.moduleRowMinHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isShowingSettings, let settings {
                VStack(alignment: .leading, spacing: 0) {
                    settings
                }
                .environment(
                    \.settingsRowLeadingPadding,
                    (leadingPadding ?? HolzBarTheme.SettingsKit.rowPaddingHorizontal)
                        + HolzBarTheme.SettingsKit.openAreaInset
                        - HolzBarTheme.SettingsKit.rowPaddingHorizontal
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HolzBarTheme.Palette.text.opacity(openAreaFill))
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The module summary as the hint of the module's switch.
private struct SettingsModuleHint: ViewModifier {
    let summary: Text?

    func body(content: Content) -> some View {
        if let summary {
            content.accessibilityHint(summary)
        } else {
            content
        }
    }
}

extension SettingsModuleRow where Settings == EmptyView {
    /// A module row without settings and without a chevron.
    init(
        _ entry: SettingsEntry,
        systemImage: String,
        isOn: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil
    ) {
        self.init(
            label: SettingsRowTitle(entry),
            summary: (entry.summary ?? entry.info).map { Text($0) },
            systemImage: systemImage,
            isOn: isOn,
            small: small,
            badge: badge
        )
    }

    /// A module row for a rule row without settings and without a chevron.
    init(
        _ title: Text,
        summary: Text?,
        systemImage: String,
        isOn: Binding<Bool>,
        small: Text? = nil,
        badge: SettingsBadge? = nil
    ) {
        self.init(
            label: SettingsRowTitle(title),
            summary: summary,
            systemImage: systemImage,
            isOn: isOn,
            small: small,
            badge: badge
        )
    }
}
