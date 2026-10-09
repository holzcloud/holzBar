//
//  KeyCap.swift
//  holzBar
//

import SwiftUI

/// A keyboard shortcut or a single key, drawn as a small cap.
struct KeyCap: View {
    private let text: String

    /// Creates a key cap.
    ///
    /// - Parameter text: The key or the symbols of the shortcut, such as "⌘⇧Space".
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(HolzBarTheme.Typography.mono)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .padding(.horizontal, HolzBarTheme.Spacing.xs - 2)
            .padding(.vertical, HolzBarTheme.Spacing.xxs / 2)
            .background(
                HolzBarTheme.Palette.groundElevated,
                in: HolzBarTheme.shape(HolzBarTheme.Radius.keyCap)
            )
            .overlay {
                HolzBarTheme.shape(HolzBarTheme.Radius.keyCap)
                    .stroke(
                        HolzBarTheme.Palette.stroke,
                        lineWidth: HolzBarTheme.Spacing.hairline
                    )
            }
            .accessibilityLabel(Text(verbatim: text))
    }
}

#Preview("KeyCap") {
    HStack {
        KeyCap("⌘")
        KeyCap("⇧")
        KeyCap("Space")
    }
    .padding()
    .background(HolzBarTheme.Palette.ground)
}
