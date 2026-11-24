//
//  DockBadgesSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Dock badges module's settings, in the open area of the module's row: the apps currently in
/// the Dock, in the Dock's order, one switch each, and the lines that say why the list is empty
/// or cannot be read. The list is read only while this view is shown and the module is on, and
/// dropped when it goes.
///
/// The states, in order: with the module off only a line that says to switch it on, and nothing
/// is read; without Accessibility a warning line with the button that asks for it, and an empty
/// list that says so; a Dock that could not be read, a warning line; a Dock without apps, an
/// empty row. The first read draws no spinner: the rows appear when they arrive.
struct DockBadgesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let isModuleOn = appState.modules.isEnabled(DockBadges.moduleID)
        let hasAccess = appState.permissions.accessibility.hasPermission
        let dockBadges = appState.dockBadges
        VStack(alignment: .leading, spacing: 0) {
            if isModuleOn {
                if !hasAccess {
                    accessibilityLine
                } else if dockBadges.listState == .unreadable {
                    SettingsStateLine(.warning, Text("The Dock could not be read. Reopen this list to try again."))
                }
                appsHeader
                appsList(hasAccess: hasAccess)
                appsFootnote
            } else {
                SettingsEmptyRow(systemImage: "app.badge", Text("Switch on Dock badges to choose apps."))
            }
        }
        .onAppear {
            dockBadges.settingsDidAppear()
        }
        .onDisappear {
            dockBadges.settingsDidDisappear()
        }
    }

    /// The warning that Accessibility is missing, with the explanation and the button that asks.
    private var accessibilityLine: some View {
        SettingsStateLine(.warning, Text("Accessibility is not granted")) {
            SettingsInfoButton(Text("holzBar reads the badge numbers on the Dock's icons through Accessibility. It reads nothing else and sends nothing anywhere."))
            Button("Grant Accessibility…") {
                appState.permissions.accessibility.performRequest()
            }
        }
    }

    /// The rows of the apps, or the empty row that says why there are none. Before the first read
    /// finishes the list is empty and draws nothing, so a chosen app never shows as gone for a
    /// moment.
    @ViewBuilder
    private func appsList(hasAccess: Bool) -> some View {
        let settings = appState.settings.dockBadges
        let dockBadges = appState.dockBadges
        if !hasAccess {
            SettingsEmptyRow(systemImage: "hand.raised", Text("Grant Accessibility to list the apps in your Dock."))
        } else {
            let rows = dockBadges.listState == .notRead ? [] : dockBadges.rows(chosen: settings.apps)
            if rows.isEmpty, dockBadges.listState == .read {
                SettingsEmptyRow(
                    systemImage: "dock.rectangle",
                    Text("No apps in the Dock. Add an app to the Dock to choose it here.")
                )
            }
            ForEach(rows) { row in
                SettingsToggleRow(
                    Text(verbatim: row.name),
                    isOn: Binding(
                        get: { settings.isChosen(row.bundleID) },
                        set: { settings.setChosen(row.bundleID, $0) }
                    ),
                    small: row.isChosen && !row.isInDock && dockBadges.listState == .read ? Text("Not in Dock") : nil
                )
                .help(row.name)
            }
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
