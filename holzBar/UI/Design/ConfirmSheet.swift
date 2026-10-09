//
//  ConfirmSheet.swift
//  holzBar
//

import SwiftUI

/// A confirmation that says exactly what will happen, for actions that change something
/// lasting or that run code the user chose.
///
/// The safe choice is the default button; the confirming button is never the default for a
/// destructive action.
struct ConfirmSheet: View {
    private let title: Text
    private let message: Text
    private let confirmTitle: LocalizedStringKey
    private let cancelTitle: LocalizedStringKey
    private let isDestructive: Bool
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    init(
        title: Text,
        message: Text,
        confirmTitle: LocalizedStringKey,
        cancelTitle: LocalizedStringKey,
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var cancelShortcut: KeyboardShortcut {
        isDestructive ? .defaultAction : .cancelAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            title
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            message
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(cancelTitle, role: .cancel, action: onCancel)
                    .keyboardShortcut(cancelShortcut)
                if isDestructive {
                    Button(confirmTitle, role: .destructive, action: onConfirm)
                } else {
                    Button(confirmTitle, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(HolzBarTheme.Palette.accent)
                }
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 420)
        .background(HolzBarTheme.Palette.ground)
    }
}

#Preview("ConfirmSheet") {
    ConfirmSheet(
        title: Text(verbatim: "Run this script?"),
        message: Text(verbatim: "The script in your scripts folder will run with your permissions."),
        confirmTitle: "Run",
        cancelTitle: "Cancel",
        onConfirm: {},
        onCancel: {}
    )
}
