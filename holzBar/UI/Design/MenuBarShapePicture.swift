//
//  MenuBarShapePicture.swift
//  holzBar
//

import SwiftUI

/// The picture of a menu bar shape on its card: a strip of dots for the items, with no shape
/// behind them, one pill behind all of them (single), one pill at each end (paired) or one pill
/// for each group (sections). It is still.
struct MenuBarShapePicture: View {
    let kind: MenuBarShapeKind

    /// The size of an item in the picture.
    private static var dotSize: CGFloat { HolzBarTheme.Spacing.xs }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            switch kind {
            case .noShape:
                dots(3)
            case .full:
                pill(3)
            case .split:
                pill(1)
                pill(2)
            case .sections:
                pill(1)
                pill(1)
                pill(1)
            }
        }
        .frame(height: HolzBarTheme.Spacing.lg)
    }

    private func dots(_ count: Int) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .fill(HolzBarTheme.Palette.textSecondary)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
    }

    private func pill(_ count: Int) -> some View {
        dots(count)
            .padding(.horizontal, HolzBarTheme.Spacing.xxs)
            .frame(height: HolzBarTheme.Spacing.lg)
            .background(HolzBarTheme.Palette.accent.opacity(0.3), in: Capsule())
    }
}

#Preview("MenuBarShapePicture") {
    HStack {
        ForEach(MenuBarShapeKind.allCases) { kind in
            PictureCard(kind.localized, isSelected: kind == .full, action: {}, picture: {
                MenuBarShapePicture(kind: kind)
            })
        }
    }
    .padding()
    .frame(width: 440)
    .background(HolzBarTheme.Palette.groundBottom)
}
