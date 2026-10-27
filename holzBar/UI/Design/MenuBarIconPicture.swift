//
//  MenuBarIconPicture.swift
//  holzBar
//

import SwiftUI

extension ControlItemImageSet.Name {
    /// The name of the style on its card.
    var localized: LocalizedStringKey {
        switch self {
        case .logo: "holzBar"
        case .chevron: "Chevron"
        case .arrow: "Arrow"
        case .eye: "Eye"
        case .ellipsis: "Dots"
        case .grid: "Grid"
        case .panel: "Panel"
        case .dot: "Dot"
        case .door: "Door"
        case .iceCube: "Ice Cube"
        case .sunglasses: "Sunglasses"
        case .custom: "Custom"
        }
    }
}

/// The small picture of a menu bar icon style on its card: the icon, as it stands in the menu bar
/// while items are hidden, on a strip of the menu bar's height. It is still.
struct MenuBarIconPicture: View {
    @Environment(AppState.self) private var appState

    let imageSet: ControlItemImageSet

    /// The height of the icon.
    private static var iconSize: CGFloat { HolzBarTheme.Spacing.md }

    var body: some View {
        icon
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
            .frame(height: HolzBarTheme.Spacing.lg)
            .background(HolzBarTheme.Palette.groundElevated, in: HolzBarTheme.shape(HolzBarTheme.Radius.keyCap))
    }

    @ViewBuilder
    private var icon: some View {
        if let image = imageSet.hidden.nsImage(for: appState) {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(HolzBarTheme.Palette.text)
                .frame(maxHeight: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: Self.iconSize, height: Self.iconSize)
        }
    }
}

/// The picture of the card for no icon: an empty slot in the strip.
struct MenuBarNoIconPicture: View {
    var body: some View {
        HolzBarTheme.shape(HolzBarTheme.Radius.keyCap)
            .strokeBorder(
                HolzBarTheme.Palette.textSecondary,
                style: StrokeStyle(lineWidth: HolzBarTheme.Spacing.hairline, dash: [3, 3])
            )
            .frame(width: HolzBarTheme.Spacing.xxl, height: HolzBarTheme.Spacing.lg)
    }
}
