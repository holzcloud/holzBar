//
//  PictureCard.swift
//  holzBar
//

import SwiftUI

/// A choice shown as a small picture with a name under it, such as the animation styles. One
/// card of a row is selected; the row is a radio group.
///
/// The card is plain, not glass: it sits in a group that is the glass layer, and nothing inside
/// glass is glass again. A selected card has the accent border and a check mark, so the choice is
/// never told by colour alone. The picture is decoration of the name, so VoiceOver reads the name
/// and "selected".
struct PictureCard<Picture: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: LocalizedStringKey
    private let isSelected: Bool
    private let action: () -> Void
    private let picture: Picture

    /// The height of the picture's well.
    private static var wellHeight: CGFloat { HolzBarTheme.Spacing.xxl + HolzBarTheme.Spacing.md }

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - title: The name under the picture.
    ///   - isSelected: Whether this card is the chosen one.
    ///   - action: Called when the card is clicked.
    ///   - picture: The small picture. It is drawn in a well of a fixed height and has no
    ///     text.
    init(
        _ title: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder picture: () -> Picture
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.picture = picture()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: HolzBarTheme.Spacing.xs) {
                picture
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.wellHeight)
                    .background(HolzBarTheme.Palette.ground, in: HolzBarTheme.shape(HolzBarTheme.Radius.control))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(HolzBarTheme.Palette.accent)
                                .padding(HolzBarTheme.Spacing.xxs)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.text)
            }
            .padding(HolzBarTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: HolzBarTheme.minimumTargetSize)
            .background(HolzBarTheme.Palette.groundElevated, in: HolzBarTheme.shape(HolzBarTheme.Radius.card))
            .overlay {
                HolzBarTheme.shape(HolzBarTheme.Radius.card)
                    .stroke(
                        isSelected ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.stroke,
                        lineWidth: isSelected ? 2 : HolzBarTheme.Spacing.hairline
                    )
            }
            .contentShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
        }
        .buttonStyle(.plain)
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.snappy, reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("PictureCard") {
    HStack {
        PictureCard("Smooth", isSelected: true, action: {}, picture: {
            Image(systemName: "waveform")
        })
        PictureCard("Fade", isSelected: false, action: {}, picture: {
            Image(systemName: "circle.lefthalf.filled")
        })
    }
    .padding()
    .frame(width: 320)
    .background(HolzBarTheme.Palette.groundBottom)
}
