//
//  NotchHubSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's own settings: whether resting the pointer opens it, which displays it opens
/// on, and its hotkey. The Modules pane shows it under the module's row while the module is on.
struct NotchHubSettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: NotchHubSettings

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Open on hover", isOn: $settings.opensOnHover)
            caption(Text("The pointer has to rest at the notch, or at the top centre on a display without one."))
            HolzBarPicker("Show the hub on", selection: $settings.displays) {
                ForEach(NotchHubDisplays.allCases, id: \.self) { displays in
                    Text(displays.localized).tag(displays)
                }
            }
            if let hotkey = appState.settings.hotkeys.hotkey(withAction: .toggleNotchHub) {
                HotkeyRecorder(hotkey: hotkey, settings: appState.settings.hotkeys) {
                    Text(HotkeyAction.toggleNotchHub.title)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
