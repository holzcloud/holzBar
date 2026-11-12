//
//  ProfilesAndHistorySettingsPane.swift
//  holzBar
//

import SwiftUI

/// The Profiles & History pane of the Settings window.
struct ProfilesAndHistorySettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SettingsPaneHost(.profilesAndHistory) {
            if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
                AutoHiddenMenuBarState(kind: .arrange)
            } else {
                ProfilesSection(profiles: appState.profiles)
                ItemGroupsSection(groups: appState.itemGroups, itemManager: appState.itemManager)
                SpacersSection(spacers: appState.spacers)
                LayoutHistorySection(snapshots: appState.snapshots)
            }
        }
    }
}
