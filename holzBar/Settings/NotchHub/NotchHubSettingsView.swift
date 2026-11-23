//
//  NotchHubSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's own settings: whether it opens on what is active, whether resting the pointer
/// opens it, whether scrolling on the notch does, which displays it opens on and how it treats the
/// camera cutout. Its hotkey is in Hotkeys. Shown in the open area of the module's row.
struct NotchHubSettingsView: View {
    @Bindable var settings: NotchHubSettings

    var body: some View {
        SettingsToggleRow(.modulesNotchHubShowsActiveFirst, isOn: $settings.showsActiveFirst)
        SettingsToggleRow(.modulesNotchHubOpensOnHover, isOn: $settings.opensOnHover)
        SettingsToggleRow(.modulesNotchHubGestures, isOn: $settings.gestures, badge: .preview)
        SettingsPickerRow(.modulesNotchHubDisplays, selection: $settings.displays, badge: .preview) {
            ForEach(NotchHubDisplays.allCases, id: \.self) { displays in
                Text(displays.localized).tag(displays)
            }
        }
        SettingsPickerRow(.modulesNotchHubCutout, selection: $settings.cutoutOverride, badge: .preview) {
            ForEach(DisplayCutoutOverride.allCases, id: \.self) { cutout in
                Text(cutout.localized).tag(cutout)
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
        case .followPointer: "Follow the pointer"
        }
    }
}

private extension DisplayCutoutOverride {
    /// The choice's name in the picker.
    var localized: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .notch: "Notch"
        case .island: "Dynamic Island"
        case .none: "None"
        }
    }
}
