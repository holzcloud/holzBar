//
//  MenuBarAppearanceSettingsPane.swift
//  holzBar
//

import SwiftUI

struct MenuBarAppearanceSettingsPane: View {
    var appearanceManager: MenuBarAppearanceManager

    var body: some View {
        MenuBarAppearanceEditor(appearanceManager: appearanceManager, location: .settings)
    }
}
