//
//  SettingsView.swift
//  holzBar
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @Bindable var navigationState: AppNavigationState
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.sidebarRowSize) private var sidebarRowSize
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool

    /// The sidebar measures for the system's sidebar icon size (D-08).
    private var metrics: HolzBarTheme.SettingsSidebar.Metrics {
        switch sidebarRowSize {
        case .small: HolzBarTheme.SettingsSidebar.small
        case .medium: HolzBarTheme.SettingsSidebar.medium
        case .large: HolzBarTheme.SettingsSidebar.large
        @unknown default: HolzBarTheme.SettingsSidebar.medium
        }
    }

    private var sidebarTextStyle: some ShapeStyle {
        appearsActive ? .primary : .secondary
    }

    private var navigationTitle: Text {
        if navigationState.settingsSearch.isSearching {
            Text("Search Results")
        } else {
            Text(navigationState.settingsNavigationIdentifier.localized)
        }
    }

    var body: some View {
        // The sidebar is always shown, and its fixed width keeps the divider from
        // collapsing it.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarColumn
        } detail: {
            detailView
        }
        .environment(navigationState.settingsSearch)
        .navigationTitle(navigationTitle)
        .tint(HolzBarTheme.Palette.accent)
        .onExitCommand {
            if navigationState.settingsSearch.isSearching {
                navigationState.settingsSearch.clear()
            }
        }
    }

    // MARK: Sidebar

    /// The search field, pinned above the scrolling rows.
    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            SettingsSearchField(
                text: Bindable(navigationState.settingsSearch).query,
                isFocused: $isSearchFocused
            )
            .padding(.horizontal, HolzBarTheme.SettingsSidebar.rowPadding)
            .padding(.bottom, HolzBarTheme.SettingsSidebar.searchFieldBottomGap)
            sidebarRows
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            sidebarToolbarSpacer
        }
        .navigationSplitViewColumnWidth(min: metrics.width, ideal: metrics.width, max: metrics.width)
    }

    /// The panes in three groups: the menu bar, Modules alone between two gaps, and holzBar. The
    /// rows scroll instead of clipping at the large sidebar size.
    private var sidebarRows: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: HolzBarTheme.SettingsSidebar.rowGap) {
                groupLabel(Text("Menu Bar"))
                ForEach(SettingsNavigationIdentifier.menuBarGroup) { identifier in
                    sidebarRow(for: identifier)
                }
                sidebarGap
                ForEach(SettingsNavigationIdentifier.modulesGroup) { identifier in
                    sidebarRow(for: identifier)
                }
                sidebarGap
                groupLabel(Text("holzBar"))
                ForEach(SettingsNavigationIdentifier.appGroup) { identifier in
                    sidebarRow(for: identifier)
                }
            }
            .padding(.horizontal, HolzBarTheme.SettingsSidebar.rowPadding)
            .padding(.bottom, HolzBarTheme.SettingsSidebar.rowPadding)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: selectNeighbour(offset: -1)
            case .down: selectNeighbour(offset: 1)
            default: break
            }
        }
    }

    private func groupLabel(_ title: Text) -> some View {
        title
            .font(HolzBarTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            .padding(.leading, HolzBarTheme.SettingsSidebar.rowPadding)
            .padding(.top, HolzBarTheme.SettingsSidebar.moduleGap)
            .padding(.bottom, HolzBarTheme.Spacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    /// A quiet gap between the groups.
    private var sidebarGap: some View {
        Color.clear
            .frame(height: HolzBarTheme.SettingsSidebar.moduleGap)
            .accessibilityHidden(true)
    }

    private func sidebarRow(for identifier: SettingsNavigationIdentifier) -> some View {
        // While a query is set the results replace the pane, so no row shows as selected.
        let isSelected = !navigationState.settingsSearch.isSearching
            && navigationState.settingsNavigationIdentifier == identifier
        return Button {
            navigationState.settingsNavigationIdentifier = identifier
        } label: {
            HStack(spacing: HolzBarTheme.SettingsSidebar.symbolTextGap) {
                identifier.iconResource.view
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                    .frame(width: metrics.symbolSize, height: metrics.symbolSize)
                    .accessibilityHidden(true)
                Text(identifier.localized)
                    .font(HolzBarTheme.Typography.sidebar(size: metrics.textSize))
                    .foregroundStyle(sidebarTextStyle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HolzBarTheme.SettingsSidebar.rowPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.rowHeight, maxHeight: metrics.rowHeight, alignment: .leading)
            .background(
                HolzBarTheme.Palette.accent.opacity(isSelected ? selectedFillOpacity : 0),
                in: HolzBarTheme.shape(HolzBarTheme.SettingsSidebar.rowRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedFillOpacity: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.accentFillDark
            : HolzBarTheme.SettingsKit.accentFillLight
    }

    /// Moves the selection to the previous or next pane (up and down arrow keys).
    private func selectNeighbour(offset: Int) {
        let all = SettingsNavigationIdentifier.allCases
        guard let index = all.firstIndex(of: navigationState.settingsNavigationIdentifier) else { return }
        let target = index + offset
        guard all.indices.contains(target) else { return }
        navigationState.settingsNavigationIdentifier = all[target]
    }

    @ToolbarContentBuilder
    private var sidebarToolbarSpacer: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        if #available(macOS 26.0, *) {
            detailContent
                .scrollEdgeEffectStyle(.hard, for: .top)
                .background(HolzBarGround(showsGlows: false))
        } else {
            detailContent
                .background(HolzBarGround(showsGlows: false))
        }
    }

    /// The results while a query is set, the selected pane otherwise.
    @ViewBuilder
    private var detailContent: some View {
        if navigationState.settingsSearch.isSearching {
            SettingsSearchResultsView()
        } else {
            settingsPane
        }
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .showingAndHiding:
            ShowingAndHidingSettingsPane()
        case .shelf:
            HolzBarShelfSettingsPane()
        case .profilesAndHistory:
            ProfilesAndHistorySettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .automation:
            AutomationSettingsPane(manager: appState.automation)
        case .modules:
            ModulesSettingsPane()
        case .general:
            GeneralSettingsPane(settings: appState.settings.general)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .about:
            AboutSettingsPane()
        }
    }
}
