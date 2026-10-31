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

    /// The model for the Notch hub's settings.
    let notchHub = NotchHubSettings()

    /// The model for the Calendar module's settings.
    let calendar = CalendarSettings()

    /// The model for the Timers module's settings.
    let timers = TimersSettings()

    /// The model for the Live activities module's settings.
    let liveActivities = LiveActivitiesSettings()

    /// Performs the initial setup of the settings model.
    func performSetup(with appState: AppState) {
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        notchHub.performSetup(with: appState)
        timers.performSetup(with: appState)
        calendar.performSetup(with: appState)
        liveActivities.performSetup(with: appState)
    }
}
