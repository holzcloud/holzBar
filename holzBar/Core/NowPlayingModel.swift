//
//  NowPlayingModel.swift
//  holzBar
//

import Foundation

/// What is playing, per player, and which player the hub shows.
///
/// One state and one ``PlaybackClock`` per ``NowPlayingPlayer``, at most ``maxPlayers``; a ninth
/// player makes the one heard least recently drop. The current player is the one that plays,
/// else one that is paused, else one that is stopped; among equals the one heard last wins.
/// Recency is a counter, not a date, so the model is deterministic.
nonisolated struct NowPlayingModel: Equatable, Sendable {
    /// The most players held at once.
    static let maxPlayers = 8

    private struct Entry: Equatable, Sendable {
        var event: NowPlayingEvent
        var clock: PlaybackClock
        var heard: Int
    }

    private var entries = [NowPlayingPlayer: Entry]()
    private var counter = 0

    /// Whether no player is known.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Takes an event heard at `now` (seconds of a monotonic clock).
    mutating func handle(_ event: NowPlayingEvent, at now: Double) {
        counter += 1
        var entry = entries[event.player] ?? Entry(event: event, clock: PlaybackClock(), heard: counter)
        var effective = event
        if effective.track == nil, effective.state != .stopped {
            // A state change without a song is about the song that was loaded.
            effective.track = entry.event.track
        }
        entry.clock.apply(effective, at: now)
        entry.event = effective
        entry.heard = counter
        entries[event.player] = entry
        while entries.count > Self.maxPlayers,
              let oldest = entries.min(by: { $0.value.heard < $1.value.heard })?.key {
            entries[oldest] = nil
        }
    }

    /// Forgets one player, for instance when it quits.
    mutating func clear(_ player: NowPlayingPlayer) {
        entries[player] = nil
    }

    /// Forgets every player.
    mutating func removeAll() {
        entries.removeAll()
    }

    /// The player to show and its latest event, or `nil` when none is known.
    var current: (player: NowPlayingPlayer, event: NowPlayingEvent)? {
        let best = entries.max { lhs, rhs in
            let left = Self.rank(lhs.value.event.state)
            let right = Self.rank(rhs.value.event.state)
            return left == right ? lhs.value.heard < rhs.value.heard : left < right
        }
        return best.map { ($0.key, $0.value.event) }
    }

    /// The position of a player's song at `now`, or `nil` when the player is not known.
    func position(of player: NowPlayingPlayer, at now: Double) -> Double? {
        entries[player]?.clock.position(at: now)
    }

    /// The players held, for a caller that wants to know what is known.
    var players: [NowPlayingPlayer] {
        Array(entries.keys)
    }

    private static func rank(_ state: NowPlaybackState) -> Int {
        switch state {
        case .playing: 2
        case .paused: 1
        case .stopped: 0
        }
    }
}
