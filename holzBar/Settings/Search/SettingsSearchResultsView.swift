//
//  SettingsSearchResultsView.swift
//  holzBar
//

import SwiftUI

/// What the Settings window shows in place of a pane while a query is set: the found settings,
/// grouped per pane, or an empty state when nothing matches (D-25). A hit is a link: a click (or
/// Return in the search field for the first hit) opens its pane and leads to its row (D-64). A hit
/// inside a disclosure shows an "Open" button instead of a chevron.
struct SettingsSearchResultsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsSearchModel.self) private var search

    private var navigationState: AppNavigationState {
        appState.navigationState
    }

    var body: some View {
        let groups = SettingsSearch.grouped(search.results)
        VStack(alignment: .leading, spacing: 0) {
            PreviewBadge()
                .padding(.horizontal, HolzBarTheme.SettingsKit.paneMarginHorizontal)
                .padding(.top, HolzBarTheme.SettingsKit.paneMarginTop)
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
                            paneResults(group.pane, entries: group.entries)
                        }
                    }
                    .padding(.horizontal, HolzBarTheme.SettingsKit.paneMarginHorizontal)
                    .padding(.top, HolzBarTheme.SettingsKit.groupGap)
                    .padding(.bottom, HolzBarTheme.SettingsKit.paneMarginBottom)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// The hits of one pane under the pane's header.
    private func paneResults(_ pane: SettingsPaneID, entries: [SettingsEntry]) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.groupHeaderGap) {
            paneHeader(pane)
            SettingsGroup {
                ForEach(entries) { entry in
                    resultRow(entry)
                }
            }
        }
    }

    /// The pane's symbol and name; a click opens the pane (concept 9a).
    private func paneHeader(_ pane: SettingsPaneID) -> some View {
        let identifier = SettingsNavigationIdentifier(pane)
        return Button {
            navigationState.settingsNavigationIdentifier = identifier
        } label: {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                identifier.iconResource.view
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                    .frame(
                        width: HolzBarTheme.SettingsKit.moduleSymbolSize,
                        height: HolzBarTheme.SettingsKit.moduleSymbolSize
                    )
                    .accessibilityHidden(true)
                Text(identifier.localized)
                    .font(HolzBarTheme.Typography.callout.weight(.semibold))
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            .padding(.leading, HolzBarTheme.SettingsKit.groupHeaderInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }

    /// One hit. The texts come from the catalogue and are already localized.
    @ViewBuilder
    private func resultRow(_ entry: SettingsEntry) -> some View {
        let small = entry.group.isEmpty ? nil : Text(verbatim: entry.group)
        if entry.disclosure == nil {
            Button {
                navigationState.revealSetting(entry)
            } label: {
                SettingsRow(Text(verbatim: entry.label), small: small) {
                    Image(systemName: "chevron.right")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            SettingsRow(Text(verbatim: entry.label), small: small) {
                Button("Open") {
                    navigationState.revealSetting(entry)
                }
            }
        }
    }
}
