//
//  AnimationStylePicture.swift
//  holzBar
//

import SwiftUI

extension RevealAnimationStyle {
    /// The name of the style.
    var localized: LocalizedStringKey {
        switch self {
        case .instant: "Instant"
        case .smooth: "Smooth"
        case .fade: "Fade"
        }
    }
}

/// The small picture of an animation style on its card: a menu bar with four items that show
/// at once (instant), arrive with a trail behind them (smooth) or appear fainter and fainter
/// (fade). It is still: nothing runs while Settings is open.
struct AnimationStylePicture: View {
    let style: RevealAnimationStyle

    /// The number of items the picture draws.
    private static let itemCount = 4

    /// The size of one item.
    private static var itemSize: CGFloat { HolzBarTheme.Spacing.sm }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            ForEach(0..<Self.itemCount, id: \.self) { index in
                item(at: index)
            }
        }
        .padding(.horizontal, HolzBarTheme.Spacing.sm)
        .frame(height: HolzBarTheme.Spacing.lg)
        .background(HolzBarTheme.Palette.groundElevated, in: HolzBarTheme.shape(HolzBarTheme.Radius.keyCap))
    }

    @ViewBuilder
    private func item(at index: Int) -> some View {
        switch style {
        case .instant:
            dot(opacity: 1)
        case .smooth:
            // The first items still travel: faint copies trail behind them.
            ZStack {
                if index < 2 {
                    dot(opacity: 0.18).offset(x: -HolzBarTheme.Spacing.md)
                    dot(opacity: 0.38).offset(x: -HolzBarTheme.Spacing.sm)
                }
                dot(opacity: 1)
            }
        case .fade:
            dot(opacity: 1 - Double(index) * 0.27)
        }
    }

    private func dot(opacity: Double) -> some View {
        Circle()
            .fill(HolzBarTheme.Palette.accent.opacity(opacity))
            .frame(width: Self.itemSize, height: Self.itemSize)
    }
}

#Preview("AnimationStylePicture") {
    HStack {
        ForEach(RevealAnimationStyle.allCases) { style in
            PictureCard(style.localized, isSelected: style == .smooth, action: {}, picture: {
                AnimationStylePicture(style: style)
            })
        }
    }
    .padding()
    .frame(width: 360)
    .background(HolzBarTheme.Palette.groundBottom)
}
