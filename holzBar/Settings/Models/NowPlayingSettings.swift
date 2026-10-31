//
//  NowPlayingSettings.swift
//  holzBar
//

import Observation

/// Model for the Now Playing module's settings: which of Apple Music and Spotify it follows, and
/// whether it also reads what every other app plays. It saves itself in its `didSet`.
@MainActor
@Observable
final class NowPlayingSettings {
    /// The players the module follows. Both by default.
    var players = NowPlayingPlayers.all {
        didSet {
            Defaults.set(players.rawValue, forKey: .nowPlayingPlayers)
        }
    }

    /// Whether the module also reads what every other app plays (Read all apps), through a
    /// private macOS interface and a helper. Off by default; stored on this Mac only.
    var readsAllApps = false {
        didSet {
            Defaults.set(readsAllApps, forKey: .nowPlayingReadsAllApps)
        }
    }

    /// Whether Read all apps switched itself off for this session because the interface or the
    /// helper failed. Not stored: the runtime sets it and clears it, so the settings can say so.
    var remoteIsUnavailable = false

    /// Loads the stored settings. The defaults can hold anything, so a value no set has reads as
    /// both players, and anything but a Boolean leaves Read all apps off.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .nowPlayingPlayers) { (raw: Int) in
            players = NowPlayingPlayers(storedRawValue: raw)
        }
        Defaults.ifPresent(key: .nowPlayingReadsAllApps) { (isOn: Bool) in
            readsAllApps = isOn
        }
    }
}
