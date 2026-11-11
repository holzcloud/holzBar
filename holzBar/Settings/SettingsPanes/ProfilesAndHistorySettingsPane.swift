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
                SettingsGroup {
                    SettingsStateLine(
                        .info,
                        Text("holzBar cannot arrange menu bar items in automatically hidden menu bars.")
                    )
                }
            } else {
                SpacersSection(spacers: appState.spacers)
            }
        }
    }
}
