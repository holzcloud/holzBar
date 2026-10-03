//
//  AppSettings.swift
//  holzBar
//

import Observation

/// Top-level model for the app's settings.
///
/// Views observe the child models directly, so nothing is forwarded from them.
@MainActor
@Observable
final class AppSettings {
    /// The model for the app's Advanced settings.
    let advanced = AdvancedSettings()

    /// The model for the app's General settings.
    let general = GeneralSettings()

    /// The model for the app's Hotkeys settings.
    let hotkeys = HotkeysSettings()

    /// Performs the initial setup of the settings model.
    func performSetup(with appState: AppState) {
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
    }
}
