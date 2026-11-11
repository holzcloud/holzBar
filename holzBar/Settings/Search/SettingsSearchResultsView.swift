//
//  SettingsSearchResultsView.swift
//  holzBar
//

import SwiftUI

/// What the Settings window shows in place of a pane while a query is set: the found settings,
/// grouped per pane, or an empty state when nothing matches (D-25).
struct SettingsSearchResultsView: View {
    @Environment(SettingsSearchModel.self) private var search

    var body: some View {
        let groups = SettingsSearch.grouped(search.results)
        if groups.isEmpty {
            EmptyState(
                systemImage: "magnifyingglass",
                title: Text("No setting found"),
                message: Text("No match for “\(search.query)”.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.groupGap) {
                    ForEach(groups, id: \.pane) { group in
                        SettingsGroup {
                            ForEach(group.entries) { entry in
                                SettingsRow(Text(verbatim: entry.label)) {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, HolzBarTheme.SettingsKit.paneMarginHorizontal)
                .padding(.top, HolzBarTheme.SettingsKit.paneMarginTop)
                .padding(.bottom, HolzBarTheme.SettingsKit.paneMarginBottom)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
