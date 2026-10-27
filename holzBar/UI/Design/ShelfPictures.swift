//
//  ShelfPictures.swift
//  holzBar
//

import SwiftUI

extension HolzBarShelfStyle {
    /// The name of the style on its card.
    var localized: LocalizedStringKey {
        switch self {
        case .attached: "Attached"
        case .floating: "Floating"
        }
    }
}

extension ShelfLayout {
    /// The name of the layout on its card.
    var localized: LocalizedStringKey {
        switch self {
        case .row: "Row"
        case .grid: "Grid"
        case .column: "Column"
        }
    }
}

/// The picture of a Shelf style on its card: a strip for the menu bar and the Shelf under it,
/// touching it (attached) or a little apart as a bar of its own (floating). It is still.
struct ShelfStylePicture: View {
    let style: HolzBarShelfStyle

    /// The width of the menu bar in the picture.
    private static var barWidth: CGFloat { HolzBarTheme.Spacing.xxl * 2 }

    var body: some View {
        VStack(spacing: style == .floating ? HolzBarTheme.Spacing.xxs : 0) {
            Rectangle()
                .fill(HolzBarTheme.Palette.textSecondary.opacity(0.35))
                .frame(width: Self.barWidth, height: HolzBarTheme.Spacing.xs)
            shelf
        }
    }

    private var shelf: some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(HolzBarTheme.Palette.ground)
                    .frame(width: HolzBarTheme.Spacing.xxs, height: HolzBarTheme.Spacing.xxs)
            }
        }
        .frame(
            width: style == .floating ? Self.barWidth - HolzBarTheme.Spacing.sm : Self.barWidth,
            height: HolzBarTheme.Spacing.sm
        )
        .background(HolzBarTheme.Palette.accent.opacity(0.85), in: shelfShape)
    }

    private var shelfShape: UnevenRoundedRectangle {
        let radius = HolzBarTheme.Radius.keyCap
        return switch style {
        case .attached:
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        case .floating:
            UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
        }
    }
}

/// The picture of a Shelf layout on its card: the same small tiles in a row, in a grid or in a
/// column, on a bar. It is still.
struct ShelfLayoutPicture: View {
    let layout: ShelfLayout

    /// The number of tiles in the picture's row and the rows of its grid.
    private static let columns = 3

    var body: some View {
        content
            .padding(HolzBarTheme.Spacing.xs)
            .background(HolzBarTheme.Palette.groundElevated, in: HolzBarTheme.shape(HolzBarTheme.Radius.keyCap))
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .row:
            HStack(spacing: HolzBarTheme.Spacing.xxs) {
                tiles(Self.columns + 1)
            }
        case .grid:
            VStack(spacing: HolzBarTheme.Spacing.xxs) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: HolzBarTheme.Spacing.xxs) {
                        tiles(Self.columns)
                    }
                }
            }
        case .column:
            VStack(spacing: HolzBarTheme.Spacing.xxs) {
                tiles(Self.columns)
            }
        }
    }

    private func tiles(_ count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            Circle()
                .fill(HolzBarTheme.Palette.accent)
                .frame(width: HolzBarTheme.Spacing.xs, height: HolzBarTheme.Spacing.xs)
        }
    }
}

#Preview("ShelfPictures") {
    HStack {
        ForEach(HolzBarShelfStyle.allCases) { style in
            PictureCard(style.localized, isSelected: style == .attached, action: {}, picture: {
                ShelfStylePicture(style: style)
            })
        }
        ForEach(ShelfLayout.allCases) { layout in
            PictureCard(layout.localized, isSelected: layout == .grid, action: {}, picture: {
                ShelfLayoutPicture(layout: layout)
            })
        }
    }
    .padding()
    .frame(width: 520)
    .background(HolzBarTheme.Palette.groundBottom)
}
