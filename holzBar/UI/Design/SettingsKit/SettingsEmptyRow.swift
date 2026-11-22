//
//  SettingsEmptyRow.swift
//  holzBar
//

import SwiftUI

/// The empty state of a list inside a settings group: a symbol in the accent colour, one
/// sentence, at most one line of next step under it and at most one button (concept section 9,
/// `EmptyState`; D-26). It is laid out like a state line and dims with its group.
struct SettingsEmptyRow<Action: View>: View {
    private let systemImage: String
    private let text: Text
    private let caption: Text?
    private let action: Action

    @Environment(\.settingsParentIsOn) private var parentIsOn

    init(systemImage: String, _ text: Text, caption: Text? = nil, @ViewBuilder action: () -> Action) {
        self.systemImage = systemImage
        self.text = text
        self.caption = caption
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.stateLineGap) {
            Image(systemName: systemImage)
                .font(HolzBarTheme.Typography.callout)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                text
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                if let caption {
                    caption
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome()
        .accessibilityElement(children: .contain)
    }
}

extension SettingsEmptyRow where Action == EmptyView {
    init(systemImage: String, _ text: Text, caption: Text? = nil) {
        self.init(systemImage: systemImage, text, caption: caption) {
            EmptyView()
        }
    }
}
