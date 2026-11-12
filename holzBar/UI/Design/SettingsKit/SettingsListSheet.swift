//
//  SettingsListSheet.swift
//  holzBar
//

import SwiftUI

/// The kit's sheet host for a list the user edits (D-15): a title, the list's settings groups
/// and state lines in a scrolling area, and "Done". Escape closes it too. Nothing in it acts on
/// the list: the rows inside act at once.
struct SettingsListSheet<Content: View>: View {
    /// The width of the sheet, the same as ``ConfirmSheet``.
    private static var width: CGFloat { 420 }
    /// The smallest height of the scrolling list.
    private static var minimumListHeight: CGFloat { 120 }
    /// The largest height of the scrolling list; a longer list scrolls.
    private static var maximumListHeight: CGFloat { 320 }

    @Environment(\.dismiss) private var dismiss
    private let title: Text
    private let content: Content

    init(_ title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            title
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.groupGap) {
                    content
                }
            }
            .frame(minHeight: Self.minimumListHeight, maxHeight: Self.maximumListHeight)
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: Self.width)
        .background(HolzBarTheme.Palette.ground)
        .onExitCommand {
            dismiss()
        }
    }
}
