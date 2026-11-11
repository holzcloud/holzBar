//
//  SpacersSection.swift
//  holzBar
//

import SwiftUI

/// Adds empty items that make space between others (jordanbaird/Ice#91).
struct SpacersSection: View {
    @Bindable var spacers: MenuBarSpacers

    var body: some View {
        SettingsGroup(SettingsCatalog.ProfilesAndHistoryPane.spacers) {
            SettingsStepperRow(
                .profilesSpacerCount,
                value: $spacers.count,
                in: 0...MenuBarSpacers.maximumCount
            ) { count in
                Text(count, format: .number)
            }
            SettingsSliderRow(
                .profilesSpacerWidth,
                value: $spacers.width,
                in: 4...60,
                step: 2
            ) { width in
                Text("\(Int(width)) pt")
            }
            .settingsDependent(on: spacers.count >= 1)
        }
    }
}
