//
//  Panel.swift
//  holzBar
//

import SwiftUI

/// The surface of a floating panel such as the launcher, the clipboard or the command palette:
/// glass with the panel radius, one soft shadow and the standard padding.
///
/// The content of a panel is laid out on `groundElevated` cards or plain rows, never on more
/// glass.
struct Panel<Content: View>: View {
    private let width: CGFloat?
    private let content: Content

    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - width: The fixed width of the panel, or `nil` to take the width of the content.
    ///   - content: The content of the panel.
    init(width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        content
            .padding(HolzBarTheme.Spacing.md)
            .frame(width: width)
            .holzBarGlass(in: HolzBarTheme.shape(HolzBarTheme.Radius.panel))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 12)
            .accessibilityElement(children: .contain)
    }
}

#Preview("Panel") {
    Panel(width: 360) {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Text(verbatim: "Type anything…")
                .font(HolzBarTheme.Typography.searchField)
                .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            HStack {
                Chip(verbatim: "Files", isSelected: true) {}
                Chip(verbatim: "Apps", isSelected: false) {}
            }
        }
    }
    .padding(HolzBarTheme.Spacing.huge)
    .background(HolzBarTheme.Palette.ground)
}
