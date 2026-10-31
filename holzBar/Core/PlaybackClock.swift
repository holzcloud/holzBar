//
//  PlaybackClock.swift
//  holzBar
//

import Foundation

/// Where a song is at any moment, worked out from the playback events alone, with no timer.
///
/// A player that reports its position replaces the count; a player that does not (Apple Music)
/// is counted: the seconds a song has played are the sum of the stretches between a play and
/// the next pause. A seek inside a song is then invisible for such a player and the count can
/// drift until the next event that carries a position. All times are seconds of a monotonic
/// clock that the caller passes in; the clock has none of its own, so it is deterministic.
nonisolated struct PlaybackClock: Equatable, Sendable {
    /// The last state, or `nil` before any event.
    private(set) var state: NowPlaybackState?

    /// The identity of the song counted, or `nil` after a stop.
    private var identity: String?

    /// The length of the song in seconds, if known.
    private var duration: Double?

    /// The seconds played before the current stretch.
    private var played = 0.0

    /// When the current stretch of playing began, or `nil` while not playing.
    private var playingSince: Double?

    /// Takes one event, heard at `now`.
    mutating func apply(_ event: NowPlayingEvent, at now: Double) {
        // Close the stretch that was running; a playing event opens a new one below.
        if let since = playingSince {
            played += max(0, now - since)
            playingSince = nil
        }
        if let track = event.track {
            if track.identity != identity {
                identity = track.identity
                played = 0
                duration = track.duration
            } else {
                duration = track.duration ?? duration
            }
        }
        if event.state == .stopped {
            identity = nil
            duration = nil
            played = 0
        }
        if let position = event.position, position.isFinite, position >= 0, event.state != .stopped {
            played = position
        }
        state = event.state
        if event.state == .playing {
            playingSince = now
        }
    }

    /// The position in seconds at `now`, held between 0 and the length of the song, or `nil`
    /// before any event.
    func position(at now: Double) -> Double? {
        guard let state else {
            return nil
        }
        var seconds = played
        if state == .playing, let since = playingSince {
            seconds += max(0, now - since)
        }
        guard seconds.isFinite else {
            return 0
        }
        seconds = max(0, seconds)
        if let duration {
            seconds = min(seconds, duration)
        }
        return seconds
    }
}
