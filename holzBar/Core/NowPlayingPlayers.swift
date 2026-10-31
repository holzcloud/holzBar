//
//  NowPlayingPlayers.swift
//  holzBar
//

import Foundation

/// Which of Apple Music and Spotify the Now Playing module follows.
///
/// The raw value is stored in the settings; new players go at the end. Any stored value outside
/// the known ones reads as both players, because the defaults can hold anything.
nonisolated struct NowPlayingPlayers: OptionSet, Sendable, Equatable {
    let rawValue: Int

    /// Apple Music.
    static let music = NowPlayingPlayers(rawValue: 1)
    /// Spotify.
    static let spotify = NowPlayingPlayers(rawValue: 2)
    /// Both players: the default.
    static let all: NowPlayingPlayers = [.music, .spotify]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The set a stored value stands for: 1, 2 or 3; anything else reads as both players.
    init(storedRawValue: Int) {
        self = (1...3).contains(storedRawValue) ? NowPlayingPlayers(rawValue: storedRawValue) : .all
    }

    /// Whether the set holds Apple Music or Spotify. Any other player is not in the set.
    func contains(_ player: NowPlayingPlayer) -> Bool {
        // Spelled with the bits: `contains(.music)` would call this method again, since
        // ``NowPlayingPlayer`` also has a static `music`.
        switch player {
        case .music: rawValue & Self.music.rawValue != 0
        case .spotify: rawValue & Self.spotify.rawValue != 0
        default: false
        }
    }

    /// Whether the module shows the player: the set decides for Music and Spotify, and every
    /// other player is allowed (such players exist only when the optional route that reads all
    /// apps is on).
    func allows(_ player: NowPlayingPlayer) -> Bool {
        player == .music || player == .spotify ? contains(player) : true
    }
}
