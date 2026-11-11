//
//  SettingsRowChrome.swift
//  holzBar
//

import SwiftUI

private nonisolated struct SettingsRowLeadingPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private nonisolated struct SettingsParentIsOnKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The leading padding of kit rows; `nil` means the row padding. Sub rows and a module row's
    /// open area raise it, and the raises add up (D-17).
    nonisolated var settingsRowLeadingPadding: CGFloat? {
        get { self[SettingsRowLeadingPaddingKey.self] }
        set { self[SettingsRowLeadingPaddingKey.self] = newValue }
    }

    /// False inside a dependent row whose parent switch is off; the rows then dim and disable
    /// their controls (D-17).
    nonisolated var settingsParentIsOn: Bool {
        get { self[SettingsParentIsOnKey.self] }
        set { self[SettingsParentIsOnKey.self] = newValue }
    }
}

/// The chrome of one row of a settings group (D-16, D-17): the hairline above it, the paddings,
/// the minimum height and the leading inset. The hairline is part of the layout, not an overlay,
/// and the group pulls the first one out of view (D-51).
struct SettingsRowChrome: ViewModifier {
    /// The id of the catalogue entry the row shows; 89-03 attaches the reveal id and the
    /// highlight to it.
    let entryID: String?
    let minHeight: CGFloat
    let verticalPadding: CGFloat
    let trailingPadding: CGFloat

    @Environment(\.settingsRowLeadingPadding) private var leadingPadding

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(HolzBarTheme.Palette.stroke)
                .frame(height: HolzBarTheme.Spacing.hairline)
                .accessibilityHidden(true)
            content
                .padding(.vertical, verticalPadding)
                .padding(.leading, leadingPadding ?? HolzBarTheme.SettingsKit.rowPaddingHorizontal)
                .padding(.trailing, trailingPadding)
                .frame(minHeight: minHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// Makes any content one row of a settings group: the hairline above it, the paddings, the
    /// minimum height and the leading inset of sub rows and open areas. Panes use it only for
    /// content no kit row expresses; content inside a group that does not use it loses its top
    /// point to the group's first-hairline clip.
    func settingsRowChrome(
        entryID: String? = nil,
        minHeight: CGFloat = HolzBarTheme.SettingsKit.rowMinHeight,
        verticalPadding: CGFloat = HolzBarTheme.SettingsKit.rowPaddingVertical,
        trailingPadding: CGFloat = HolzBarTheme.SettingsKit.rowPaddingHorizontal
    ) -> some View {
        modifier(SettingsRowChrome(
            entryID: entryID,
            minHeight: minHeight,
            verticalPadding: verticalPadding,
            trailingPadding: trailingPadding
        ))
    }
}

/// Starts the rows inside further in (D-17): adds the sub row inset to whatever the leading
/// padding is, so nested insets add up. Every kit row, the module row and the picture card row
/// honour it.
private struct SettingsSubRowModifier: ViewModifier {
    @Environment(\.settingsRowLeadingPadding) private var current

    func body(content: Content) -> some View {
        content.environment(
            \.settingsRowLeadingPadding,
            (current ?? HolzBarTheme.SettingsKit.rowPaddingHorizontal) + HolzBarTheme.SettingsKit.subRowInset
        )
    }
}

/// Makes the rows inside depend on a parent switch (D-17): while it is off they stay visible at
/// reduced opacity with only their controls disabled. A row inside two dependencies is off when
/// either parent is. Every kit row, the module row and the picture card row honour it.
private struct SettingsDependentModifier: ViewModifier {
    let parentIsOn: Bool

    @Environment(\.settingsParentIsOn) private var current

    func body(content: Content) -> some View {
        content.environment(\.settingsParentIsOn, current && parentIsOn)
    }
}

extension View {
    /// Starts this row or block 18 pt further in, like a sub row of a setting (D-17).
    func settingsSubRow() -> some View {
        modifier(SettingsSubRowModifier())
    }

    /// Dims this row or block and disables its controls while `parentIsOn` is false (D-17).
    func settingsDependent(on parentIsOn: Bool) -> some View {
        modifier(SettingsDependentModifier(parentIsOn: parentIsOn))
    }
}
