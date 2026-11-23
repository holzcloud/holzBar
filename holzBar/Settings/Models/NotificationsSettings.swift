//
//  NotificationsSettings.swift
//  holzBar
//

import Observation

/// Model for the Notifications module's own settings: the apps whose notifications the hub never
/// shows, and how long a new notification shows as a count in the closed notch. Each saves itself
/// in its `didSet`. The list names apps the user runs, so it is local to this Mac (never exported
/// or imported); the display time is a plain number and travels with a settings file.
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

    /// How long a new notification shows as a count in the closed notch, in seconds: one of
    /// ``DesignTokens/Indicator/notificationDisplayTimes``, 5 by default. The picker offers only
    /// those; what is stored is snapped to the nearest one.
    var displayTime = DesignTokens.Indicator.notificationDefaultDisplayTime {
        didSet {
            guard displayTime != oldValue else {
                return
            }
            Defaults.set(displayTime, forKey: .notificationsDisplayTime)
        }
    }

    /// Loads the stored settings. They can hold anything, so the list is cleaned and the display
    /// time is clamped to its range and snapped to the nearest choice.
    func performSetup(with appState: AppState) {
        if let stored = Defaults.stringArray(forKey: .notificationsExcludedApps) {
            excludedApps = NotificationLog.cleanedExclusions(stored)
        }
        Defaults.ifPresent(key: .notificationsDisplayTime) { (stored: Double) in
            let clamped = Defaults.Key.notificationsDisplayTime.clamped(
                stored,
                fallback: Double(DesignTokens.Indicator.notificationDefaultDisplayTime)
            )
            displayTime = NotificationQueue.displayTime(Int(clamped.rounded(.down)))
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
