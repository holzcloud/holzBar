//
//  MenuBarAppearanceSettingsPane.swift
//  holzBar
//

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    var appearanceManager: MenuBarAppearanceManager

    var body: some View {
        SettingsPaneHost(.appearance) {
            MenuBarAppearanceEditor(appearanceManager: appearanceManager, location: .settings)
        }
    }
}
