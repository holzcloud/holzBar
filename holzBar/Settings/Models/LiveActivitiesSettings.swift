//
//  LiveActivitiesSettings.swift
//  holzBar
//

import Observation

/// Model for the Live activities module's own settings: which sources report activities. Each
/// saves itself in its `didSet`.
@MainActor
@Observable
final class LiveActivitiesSettings {
    /// A Boolean value that indicates whether a camera or the microphone in use by another app is
    /// an activity. It needs no permission, so it is on by default.
    var capturesInUse = true {
        didSet {
            Defaults.set(capturesInUse, forKey: .liveActivitiesCapture)
        }
    }

    /// A Boolean value that indicates whether downloads in progress are activities. Off by
    /// default: switching it on opens the Downloads folder, which is when macOS asks the user.
    var watchesDownloads = false {
        didSet {
            Defaults.set(watchesDownloads, forKey: .liveActivitiesDownloads)
        }
    }

    /// Loads the stored settings.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .liveActivitiesCapture, assign: &capturesInUse)
        Defaults.ifPresent(key: .liveActivitiesDownloads, assign: &watchesDownloads)
    }
}
