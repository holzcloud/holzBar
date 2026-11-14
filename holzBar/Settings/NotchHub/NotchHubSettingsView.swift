//
//  NotchHubSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's own settings: whether it opens on what is active, whether resting the pointer
/// opens it and which displays it opens on. Its hotkey is in Hotkeys. Shown in the open area of the module's row.
struct NotchHubSettingsView: View {
    @Bindable var settings: NotchHubSettings

    var body: some View {
        SettingsToggleRow(.modulesNotchHubShowsActiveFirst, isOn: $settings.showsActiveFirst)
        SettingsToggleRow(.modulesNotchHubOpensOnHover, isOn: $settings.opensOnHover)
        SettingsPickerRow(.modulesNotchHubDisplays, selection: $settings.displays) {
            ForEach(NotchHubDisplays.allCases, id: \.self) { displays in
                Text(displays.localized).tag(displays)
            }
        }
    }
}

private extension NotchHubDisplays {
    /// The choice's name in the picker.
    var localized: LocalizedStringKey {
        switch self {
        case .all: "All displays"
        case .builtIn: "Built-in display only"
        case .notched: "Displays with a notch only"
        }
    }
}
