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
