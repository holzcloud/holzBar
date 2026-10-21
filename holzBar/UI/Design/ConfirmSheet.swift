//
//  ConfirmSheet.swift
//  holzBar
//

import SwiftUI

/// A confirmation that says exactly what will happen, for actions that change something
/// lasting or that run code the user chose.
///
/// The safe choice is the default button; the confirming button is never the default for a
/// destructive action. Escape always cancels.
///
/// The message is optional, for a question that needs no more than its title. A secondary
/// action, such as "Open System Settings", sits at the leading edge of the buttons.
struct ConfirmSheet: View {
    private let title: Text
    private let message: Text?
    private let confirmTitle: LocalizedStringKey
    private let cancelTitle: LocalizedStringKey
    private let isDestructive: Bool
    private let secondaryTitle: LocalizedStringKey?
    private let onSecondary: (() -> Void)?
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    init(
        title: Text,
        message: Text? = nil,
        confirmTitle: LocalizedStringKey,
        cancelTitle: LocalizedStringKey,
        isDestructive: Bool = false,
        secondaryTitle: LocalizedStringKey? = nil,
        onSecondary: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
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
            if let message {
                message
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                }
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
        .onExitCommand(perform: isDestructive ? onCancel : nil)
    }
}

extension View {
    /// Asks a question in a ConfirmSheet while `isPresented` is true.
    ///
    /// Confirming runs `onConfirm` first and closes the sheet after it: a handler may read
    /// state that closing the sheet clears. Cancel and Escape only close the sheet.
    func holzBarConfirmation(
        isPresented: Binding<Bool>,
        title: Text,
        message: Text? = nil,
        confirmTitle: LocalizedStringKey,
        cancelTitle: LocalizedStringKey = "Cancel",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmSheet(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                isDestructive: isDestructive,
                onConfirm: {
                    onConfirm()
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                }
            )
        }
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

#Preview("ConfirmSheet, destructive, with a secondary action") {
    VStack {
        ConfirmSheet(
            title: Text(verbatim: "Delete this rule?"),
            confirmTitle: "Delete",
            cancelTitle: "Cancel",
            isDestructive: true,
            onConfirm: {},
            onCancel: {}
        )
        ConfirmSheet(
            title: Text(verbatim: "Revoke this permission?"),
            message: Text(verbatim: "holzBar stops working with it until you allow it again."),
            confirmTitle: "Revoke",
            cancelTitle: "Cancel",
            isDestructive: true,
            secondaryTitle: "Open System Settings",
            onSecondary: {},
            onConfirm: {},
            onCancel: {}
        )
    }
}
