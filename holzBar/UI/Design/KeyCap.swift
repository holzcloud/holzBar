//
//  KeyCap.swift
//  holzBar
//

import SwiftUI

/// A keyboard shortcut or a single key, drawn as a small cap.
struct KeyCap: View {
    private let text: String
    private let isProminent: Bool

    /// Creates a key cap.
    ///
    /// - Parameters:
    ///   - text: The key or the symbols of the shortcut, such as "⌘⇧Space".
    ///   - isProminent: Whether the cap stands out because it is the key to press now: the
    ///     accent fill with a white label, as the hint letters of the item hints use it.
    init(_ text: String, isProminent: Bool = false) {
        self.text = text
        self.isProminent = isProminent
    }

    var body: some View {
        Text(verbatim: text)
            .font(isProminent ? HolzBarTheme.Typography.mono.weight(.bold) : HolzBarTheme.Typography.mono)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(
                isProminent ? HolzBarTheme.Palette.onFill : HolzBarTheme.Palette.textSecondary
            )
            .padding(.horizontal, HolzBarTheme.Spacing.xs - 2)
            .padding(.vertical, HolzBarTheme.Spacing.xxs / 2)
            .background {
                if isProminent {
                    HolzBarTheme.shape(HolzBarTheme.Radius.keyCap)
                        .fill(HolzBarTheme.fillGradient)
                } else {
                    HolzBarTheme.shape(HolzBarTheme.Radius.keyCap)
                        .fill(HolzBarTheme.Palette.groundElevated)
                }
            }
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
        KeyCap("A", isProminent: true)
    }
    .padding()
    .background(HolzBarTheme.Palette.ground)
}
