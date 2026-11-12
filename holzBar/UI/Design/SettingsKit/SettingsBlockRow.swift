//
//  SettingsBlockRow.swift
//  holzBar
//

import SwiftUI

/// A full-width row of a settings group for content that the label-and-control rows cannot
/// express: the Layout bars, and later the list view of Phase 90. It takes the chrome of every kit
/// row (hairline above, paddings, minimum height), aligns its content leading at full width and
/// has no label column, no info button and no search entry; a caller sets `.id` when it needs
/// one. Unlike `SettingsPictureRow` its content is interactive, so VoiceOver reaches it. It
/// honours `settingsSubRow()` and `settingsDependent(on:)`: while the parent is off the content
/// is dimmed, disabled and not hit-testable, and the hairline keeps full strength.
struct SettingsBlockRow<Content: View>: View {
    private let content: Content

    @Environment(\.settingsParentIsOn) private var parentIsOn

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
            .disabled(!parentIsOn)
            .allowsHitTesting(parentIsOn)
            .settingsRowChrome(
                minHeight: HolzBarTheme.SettingsKit.rowMinHeight,
                verticalPadding: HolzBarTheme.SettingsKit.rowPaddingVertical,
                trailingPadding: HolzBarTheme.SettingsKit.rowPaddingHorizontal
            )
            .accessibilityElement(children: .contain)
    }
}
