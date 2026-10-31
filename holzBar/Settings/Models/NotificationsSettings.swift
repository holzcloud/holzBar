//
//  NotificationsSettings.swift
//  holzBar
//

import Observation

/// Model for the Notifications module's own setting: the apps whose notifications the hub never
/// shows. The list saves itself in its `didSet`. It names apps the user runs, so it is local to
/// this Mac (never exported or imported) and it is the only thing of the module that is stored.
@MainActor
@Observable
final class NotificationsSettings {
    /// The names of the excluded apps, as the banners state them. Trimmed, without empty names or
    /// repeats, at most ``NotificationLog/maximumExcludedApps``.
    private(set) var excludedApps = [String]() {
        didSet {
            Defaults.set(excludedApps, forKey: .notificationsExcludedApps)
        }
    }

    /// Loads the stored list. It can hold anything, so it is cleaned.
    func performSetup(with appState: AppState) {
        if let stored = Defaults.stringArray(forKey: .notificationsExcludedApps) {
            excludedApps = NotificationLog.cleanedExclusions(stored)
        }
    }

    /// Adds an app to the list, unless it is there already or the list is full.
    func exclude(_ name: String) {
        let cleaned = NotificationLog.cleanedExclusions(excludedApps + [name])
        if cleaned != excludedApps {
            excludedApps = cleaned
        }
    }

    /// Takes an app off the list.
    func include(_ name: String) {
        excludedApps = NotificationLog.cleanedExclusions(excludedApps.filter { $0 != name })
    }
}
