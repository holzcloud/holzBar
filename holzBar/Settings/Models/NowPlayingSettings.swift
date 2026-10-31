//
//  NowPlayingSettings.swift
//  holzBar
//

import Observation

/// Model for the Now Playing module's setting: which of Apple Music and Spotify it follows. It
/// saves itself in its `didSet`.
@MainActor
@Observable
final class NowPlayingSettings {
    /// The players the module follows. Both by default.
    var players = NowPlayingPlayers.all {
        didSet {
            Defaults.set(players.rawValue, forKey: .nowPlayingPlayers)
        }
    }

    /// Loads the stored setting. The defaults can hold anything, so a value no set has reads as
    /// both players.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .nowPlayingPlayers) { (raw: Int) in
            players = NowPlayingPlayers(storedRawValue: raw)
        }
    }
}
