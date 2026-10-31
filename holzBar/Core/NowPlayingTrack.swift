//
//  NowPlayingTrack.swift
//  holzBar
//

import Foundation

/// An app that plays: a value keyed by its bundle identifier, so that Apple Music, Spotify and
/// any other app a later source reports (the optional route that reads all apps) share one
/// model.
nonisolated struct NowPlayingPlayer: Hashable, Sendable {
    /// The player's bundle identifier.
    let bundleIdentifier: String

    /// Apple Music.
    static let music = NowPlayingPlayer(bundleIdentifier: "com.apple.Music")
    /// Spotify.
    static let spotify = NowPlayingPlayer(bundleIdentifier: "com.spotify.client")
}

/// What a player is doing.
nonisolated enum NowPlaybackState: Sendable {
    case playing
    case paused
    case stopped
}

/// What is known about the song a player has loaded. Every field is optional because the
/// players send what they like; a missing one is unknown, never an error.
nonisolated struct NowPlayingTrack: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    /// The length in seconds.
    var duration: Double?
    /// The audio file of a local song, always a `file` URL.
    var fileURL: URL?
    /// The player's own identifier of the song, if it sends one.
    var id: String?

    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: Double? = nil,
        fileURL: URL? = nil,
        id: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.id = id
    }

    /// What makes a song the same song: the player's identifier when there is one, otherwise
    /// the title, artist, album and length joined. Two tracks with the same identity are the
    /// same song for the model and the clock.
    var identity: String {
        if let id {
            return "id:" + id
        }
        let separator = "\u{1F}"
        return [title ?? "", artist ?? "", album ?? "", duration.map { String($0) } ?? ""]
            .joined(separator: separator)
    }
}

/// One playback notification, parsed: which player, what it is doing, the song if it said and
/// the position if it reported one.
nonisolated struct NowPlayingEvent: Equatable, Sendable {
    var player: NowPlayingPlayer
    var state: NowPlaybackState
    var track: NowPlayingTrack?
    /// The playback position in seconds, for a player that reports one.
    var position: Double?

    init(
        player: NowPlayingPlayer,
        state: NowPlaybackState,
        track: NowPlayingTrack? = nil,
        position: Double? = nil
    ) {
        self.player = player
        self.state = state
        self.track = track
        self.position = position
    }
}
