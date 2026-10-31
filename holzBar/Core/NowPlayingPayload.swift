//
//  NowPlayingPayload.swift
//  holzBar
//

import Foundation

/// Parses the playback notifications of Apple Music (and Spotify) into ``NowPlayingEvent``.
///
/// The user info of a distributed notification is data from another process: every key is
/// optional, every value is checked, and nothing here can trap. A missing or odd value is
/// unknown, an oversized text is cut, a file path that is not a `file` URL is dropped, and a
/// payload without a recognised state is ignored.
nonisolated enum NowPlayingPayload {
    /// The notification Apple Music posts when its song or state changes.
    static let musicNotification = "com.apple.Music.playerInfo"
    /// The notification Spotify posts when its song or state changes.
    static let spotifyNotification = "com.spotify.client.PlaybackStateChanged"

    /// The longest text kept, in characters.
    static let maxTextLength = 500
    /// The longest identifier kept, in characters.
    static let maxIDLength = 200
    /// The longest file location kept, in characters.
    static let maxLocationLength = 2_000
    /// The longest song accepted, in seconds (one day).
    static let maxDuration = 86_400.0

    /// The keys that differ between the two players.
    private nonisolated struct Keys: Sendable {
        let duration: String
        let id: String
        let position: String?
        let hasFile: Bool

        static let music = Keys(duration: "Total Time", id: "Persistent ID", position: nil, hasFile: true)
        static let spotify = Keys(duration: "Duration", id: "Track ID", position: "Playback Position", hasFile: false)
    }

    /// The event a notification stands for, or `nil` for an unknown name or a payload without a
    /// known state.
    static func parse(name: String, userInfo: [AnyHashable: Any]) -> NowPlayingEvent? {
        switch name {
        case musicNotification:
            return event(player: .music, userInfo: userInfo, keys: .music)
        case spotifyNotification:
            return event(player: .spotify, userInfo: userInfo, keys: .spotify)
        default:
            return nil
        }
    }

    private static func event(
        player: NowPlayingPlayer,
        userInfo: [AnyHashable: Any],
        keys: Keys
    ) -> NowPlayingEvent? {
        guard let state = state(userInfo["Player State"]) else {
            return nil
        }
        let track = NowPlayingTrack(
            title: text(userInfo["Name"]),
            artist: text(userInfo["Artist"]),
            album: text(userInfo["Album"]),
            duration: duration(milliseconds: userInfo[keys.duration]),
            fileURL: keys.hasFile ? fileURL(userInfo["Location"]) : nil,
            id: identifier(userInfo[keys.id])
        )
        let position = keys.position.flatMap { position(userInfo[$0]) }
        return NowPlayingEvent(
            player: player,
            state: state,
            track: track == NowPlayingTrack() ? nil : track,
            position: position
        )
    }

    // MARK: Values

    private static func state(_ value: Any?) -> NowPlaybackState? {
        guard let string = value as? String else {
            return nil
        }
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing": return .playing
        case "paused": return .paused
        case "stopped": return .stopped
        default: return nil
        }
    }

    /// Trimmed text; an empty string is unknown; at most ``maxTextLength`` characters.
    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maxTextLength))
    }

    private static func identifier(_ value: Any?) -> String? {
        let string: String
        if let text = value as? String {
            string = text
        } else if let number = number(value), number.isFinite {
            string = number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        } else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maxIDLength))
    }

    /// A length given in milliseconds, kept as seconds, when it is above 0 and at most a day.
    private static func duration(milliseconds value: Any?) -> Double? {
        guard let milliseconds = number(value) else {
            return nil
        }
        let seconds = milliseconds / 1_000
        guard seconds.isFinite, seconds > 0, seconds <= maxDuration else {
            return nil
        }
        return seconds
    }

    /// A position in seconds, when it is finite and not negative.
    private static func position(_ value: Any?) -> Double? {
        guard let seconds = number(value), seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return seconds
    }

    /// A `file` URL; anything else, including a web address or a bare path, is dropped.
    private static func fileURL(_ value: Any?) -> URL? {
        let url: URL?
        if let existing = value as? URL {
            url = existing
        } else if let string = value as? String, string.count <= maxLocationLength {
            url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            url = nil
        }
        guard let url, url.scheme?.lowercased() == "file", url.isFileURL else {
            return nil
        }
        return url
    }

    /// `Int`, `Double`, `Float`, `NSNumber` and a numeric `String` all count as numbers.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        case let float as Float: Double(float)
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }
}
