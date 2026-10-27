//
//  PictureCardRow.swift
//  holzBar
//

import SwiftUI

/// A choice among a few visual options as a row of picture cards under a label: the way the
/// settings show a choice of two to four things that look different (an animation, a layout, a
/// shape). The row is a radio group; the cards wrap when the pane is narrow.
///
/// A choice that is only words, or has many options, stays a menu (`HolzBarPicker`).
struct PictureCardRow<Value: Hashable, Label: View, Picture: View>: View {
    @Binding private var selection: Value
    private let values: [Value]
    private let name: (Value) -> LocalizedStringKey
    private let label: Label
    private let picture: (Value) -> Picture

    /// The smallest width of a card.
    private static var cardWidth: CGFloat { HolzBarTheme.Spacing.xxl * 2 + HolzBarTheme.Spacing.lg }

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - selection: The chosen value.
    ///   - values: The options, in the order of the cards.
    ///   - name: The name of an option, shown under its picture.
    ///   - label: The label above the cards.
    ///   - picture: The small picture of an option.
    init(
        selection: Binding<Value>,
        values: [Value],
        name: @escaping (Value) -> LocalizedStringKey,
        @ViewBuilder label: () -> Label,
        @ViewBuilder picture: @escaping (Value) -> Picture
    ) {
        self._selection = selection
        self.values = values
        self.name = name
        self.label = label()
        self.picture = picture
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            label
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: HolzBarTheme.Spacing.sm)],
                spacing: HolzBarTheme.Spacing.sm
            ) {
                ForEach(values, id: \.self) { value in
                    PictureCard(name(value), isSelected: selection == value) {
                        selection = value
                    } picture: {
                        picture(value)
                    }
                }
            }
        }
    }
}
