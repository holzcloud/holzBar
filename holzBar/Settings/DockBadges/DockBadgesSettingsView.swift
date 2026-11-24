//
//  DockBadgesSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Dock badges module's settings, in the open area of the module's row: the apps currently in
/// the Dock, in the Dock's order, one switch each. The list is read only while this view is
/// shown and the module is on, and dropped when it goes.
struct DockBadgesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let settings = appState.settings.dockBadges
        let dockBadges = appState.dockBadges
        appsHeader
        ForEach(dockBadges.rows(chosen: settings.apps)) { row in
            SettingsToggleRow(
                Text(verbatim: row.name),
                isOn: Binding(
                    get: { settings.isChosen(row.bundleID) },
                    set: { settings.setChosen(row.bundleID, $0) }
                ),
                small: row.isChosen && !row.isInDock ? Text("Not in Dock") : nil
            )
            .help(row.name)
        }
        appsFootnote
            .onAppear {
                dockBadges.settingsDidAppear()
            }
            .onDisappear {
                dockBadges.settingsDidDisappear()
            }
    }

    /// The header of the list, laid out as a row of the open area.
    private var appsHeader: some View {
        Text("Apps in the Dock")
            .font(HolzBarTheme.Typography.callout.weight(.semibold))
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome()
    }

    /// What the list holds, under it.
    private var appsFootnote: some View {
        Text("Only apps in the Dock can show a badge.")
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome()
    }
}
