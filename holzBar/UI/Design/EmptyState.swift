//
//  EmptyState.swift
//  holzBar
//

import SwiftUI

/// What a screen shows when there is nothing to show yet: a symbol, a title, one sentence
/// and, if useful, one button.
struct EmptyState: View {
    private let systemImage: String
    private let title: Text
    private let message: Text
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    init(
        systemImage: String,
        title: Text,
        message: Text,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
            title
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.text)
            message
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(HolzBarTheme.Palette.accent)
            }
        }
        .padding(HolzBarTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The quiet one-line variant of ``EmptyState`` for a strip that is only a few points tall,
/// such as a section of the menu bar layout: secondary text, no symbol, no button.
struct CompactEmptyState: View {
    private let message: Text

    init(message: Text) {
        self.message = message
    }

    var body: some View {
        message
            .font(HolzBarTheme.Typography.callout)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
    }
}

#Preview("EmptyState") {
    EmptyState(
        systemImage: "tray",
        title: Text(verbatim: "Nothing here yet"),
        message: Text(verbatim: "Switch a module on and it shows up here.")
    )
    .background(HolzBarTheme.Palette.ground)
}
