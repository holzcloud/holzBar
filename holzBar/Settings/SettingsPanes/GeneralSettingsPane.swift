//
//  GeneralSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The short landing pane: how holzBar starts, and its icon in the menu bar.
struct GeneralSettingsPane: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        SettingsPaneHost(.general) {
            SettingsGroup(SettingsCatalog.GeneralPane.startup) {
                LaunchAtLoginToggle()
                SettingsToggleRow(.generalShowWhatsNew, isOn: $settings.showsWhatsNewAfterUpdate)
            }
            SettingsGroup(SettingsCatalog.GeneralPane.icon) {
                HolzBarIconCards(settings: settings)
                SettingsToggleRow(.generalHiddenCount, isOn: $settings.showsHiddenItemCount)
                    .settingsDependent(on: settings.showHolzBarIcon)
                if #available(macOS 27.0, *) {
                    // macOS 27 hides Control Center's capture indicator while an assessment
                    // assertion hides items (MenuBarAssessmentAssertion27); holzBar can only say
                    // so and mark its own icon for the microphone and the camera.
                    SettingsStateLine(.info, Text("While holzBar hides items, Control Center does not show its indicator for the camera, the microphone or screen recording."))
                    SettingsToggleRow(
                        .generalCaptureDot,
                        isOn: $settings.holzBarIconShowsCaptureDot,
                        small: Text("macOS 27 only")
                    )
                    .settingsDependent(on: settings.showHolzBarIcon)
                }
                HolzBarIconNote(settings: settings)
            }
        }
    }
}
