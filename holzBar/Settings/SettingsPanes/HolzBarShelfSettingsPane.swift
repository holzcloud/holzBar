//
//  HolzBarShelfSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The holzBar Shelf pane of the Settings window.
struct HolzBarShelfSettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var general = appState.settings.general

        SettingsPaneHost(.shelf) {
            SettingsGroup {
                SettingsToggleRow(
                    .shelfUse,
                    isOn: $general.useShelf,
                    info: general.useShelf ? nil : Text("Off: hidden menu bar items appear in the menu bar itself. Turn it on to show them in a separate bar under the menu bar.")
                )
                SettingsPictureRow {
                    ShelfOverviewPicture(
                        isOn: general.useShelf,
                        style: general.shelfStyle,
                        layout: general.shelfLayout
                    )
                }
            }
        }
    }
}
