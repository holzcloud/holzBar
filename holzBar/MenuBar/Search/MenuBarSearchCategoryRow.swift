//
//  MenuBarSearchCategoryRow.swift
//  holzBar
//

import SwiftUI

/// The row of category chips under the search field: All first, then the categories the items
/// fall into, one selected at a time.
struct MenuBarSearchCategoryRow: View {
    /// The categories that have at least one item.
    let categories: [ItemCategory]

    /// The selected category; `nil` is All.
    @Binding var selection: ItemCategory?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Chip("All", isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(ItemCategoryChips.chips(present: categories), id: \.self) { category in
                    Chip(
                        LocalizedStringKey(category.titleKey),
                        systemImage: category.symbolName,
                        isSelected: selection == category
                    ) {
                        selection = category
                    }
                }
            }
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
    }
}
