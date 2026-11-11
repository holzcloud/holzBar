//
//  SettingsPictureCardRow.swift
//  holzBar
//

import SwiftUI

/// A row of picture cards (D-23): the label and the info button above the cards, one card per
/// value, the selected card with the accent border and a check mark. Up to four values share the
/// row's width; more are 78 pt wide and wrap. While the row is dependent and off the cards are
/// disabled and the row dims, the info button keeps working. The entry form takes label and info
/// from the catalogue; the text form is for labels that are user data.
struct SettingsPictureCardRow<Value: Hashable, Picture: View>: View {
    private let label: SettingsRowTitle
    @Binding private var selection: Value
    private let values: [Value]
    private let info: Text?
    private let name: (Value) -> Text
    private let picture: (Value) -> Picture

    @Environment(\.settingsParentIsOn) private var parentIsOn

    init(
        _ entry: SettingsEntry,
        selection: Binding<Value>,
        values: [Value],
        info: Text? = nil,
        name: @escaping (Value) -> Text,
        @ViewBuilder picture: @escaping (Value) -> Picture
    ) {
        label = SettingsRowTitle(entry)
        _selection = selection
        self.values = values
        self.info = info
        self.name = name
        self.picture = picture
    }

    init(
        _ title: Text,
        selection: Binding<Value>,
        values: [Value],
        info: Text? = nil,
        name: @escaping (Value) -> Text,
        @ViewBuilder picture: @escaping (Value) -> Picture
    ) {
        label = SettingsRowTitle(title)
        _selection = selection
        self.values = values
        self.info = info
        self.name = name
        self.picture = picture
    }

    private func card(_ value: Value) -> some View {
        PictureCard(name(value), isSelected: selection == value) {
            selection = value
        } picture: {
            picture(value)
        }
    }

    @ViewBuilder
    private var cards: some View {
        let gap = HolzBarTheme.SettingsKit.pictureCardGap
        if values.count > Int(HolzBarTheme.SettingsKit.pictureCardsBeforeCompact) {
            let width = HolzBarTheme.SettingsKit.pictureCardCompactWidth
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: gap, alignment: .top)],
                alignment: .leading,
                spacing: gap
            ) {
                ForEach(values, id: \.self) { card($0) }
            }
        } else {
            HStack(alignment: .top, spacing: gap) {
                ForEach(values, id: \.self) { card($0).frame(maxWidth: .infinity) }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.pictureCardGap) {
            SettingsLabelColumn(title: label.title, small: nil, badge: nil, info: info ?? label.info)
            cards.disabled(!parentIsOn)
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome(
            entryID: label.entryID,
            verticalPadding: HolzBarTheme.SettingsKit.pictureCardRowPaddingVertical,
            trailingPadding: HolzBarTheme.SettingsKit.pictureCardRowPaddingHorizontal
        )
        .accessibilityElement(children: .contain)
    }
}
