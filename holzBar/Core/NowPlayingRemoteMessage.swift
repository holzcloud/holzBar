//
//  NowPlayingRemoteMessage.swift
//  holzBar
//

import Foundation

/// Parses one line of the Now Playing helper's output (the optional route "Read all apps").
///
/// The helper prints one JSON object per line on its standard output: `{"v":1,"bundle":…}` for
/// the app that plays, `{"v":1,"none":true}` when nothing plays and `{"v":1,"error":…}` when it
/// could not ask. A line is data from another process: it is checked, every text and number is
/// capped, unknown keys are ignored, and nothing here can trap. Only the title, artist, album,
/// length and position cross the protocol: no picture, no file path, no track identifier.
nonisolated enum NowPlayingRemoteMessage {
    /// Why the helper could not ask, as it names the reason.
    enum Failure: String, Sendable {
        /// The private framework could not be loaded.
        case framework
        /// A function of the framework is missing.
        case symbol
        /// The framework answered that nothing is available to the helper.
        case unavailable
        /// The framework did not answer in time.
        case timeout
    }

    /// What a line stands for.
    enum Result: Equatable, Sendable {
        /// The app that plays, or the last app that did.
        case event(NowPlayingEvent)
        /// Nothing plays.
        case none
        /// The helper could not ask.
        case unavailable(Failure)
        /// The line is not a valid message.
        case invalid
    }

    /// The longest line accepted, in bytes.
    static let maxLineBytes = 65_536
    /// The longest text kept, in characters (as for the public notifications).
    static let maxTextLength = NowPlayingPayload.maxTextLength
    /// The longest bundle identifier accepted, in characters.
    static let maxBundleLength = NowPlayingPayload.maxIDLength
    /// The longest song accepted, in seconds (one day).
    static let maxDuration = NowPlayingPayload.maxDuration
    /// The protocol version this parser reads.
    static let version = 1.0

    /// The meaning of `line`, read at `now` (the position moves on by the time that has passed
    /// since the helper took it).
    static func parse(line: String, now: Date) -> Result {
        guard !line.isEmpty, line.utf8.count <= maxLineBytes,
              let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              number(object["v"]) == version else {
            return .invalid
        }
        if object["none"] as? Bool == true {
            return .none
        }
        if let reason = object["error"] {
            guard let name = reason as? String, let failure = Failure(rawValue: name) else {
                return .invalid
            }
            return .unavailable(failure)
        }
        guard let bundle = object["bundle"] as? String, isValidBundle(bundle) else {
            return .invalid
        }
        return .event(event(bundle: bundle, object: object, now: now))
    }

    // MARK: Event

    private static func event(bundle: String, object: [String: Any], now: Date) -> NowPlayingEvent {
        let title = text(object["title"])
        let track = NowPlayingTrack(
            title: title,
            artist: text(object["artist"]),
            album: text(object["album"]),
            duration: duration(object["duration"])
        )
        let isPlaying = playing(object["playing"])
        let state: NowPlaybackState
        if isPlaying {
            state = .playing
        } else {
            state = title == nil ? .stopped : .paused
        }
        return NowPlayingEvent(
            player: NowPlayingPlayer(bundleIdentifier: bundle),
            state: state,
            track: track == NowPlayingTrack() ? nil : track,
            position: position(object, isPlaying: isPlaying, duration: track.duration, now: now)
        )
    }

    /// The position at `now`: the elapsed time the helper reported, moved on by the time since
    /// its timestamp at the playback rate while the song plays, and held between 0 and the
    /// length when that is known. Unknown without a valid elapsed time.
    private static func position(
        _ object: [String: Any],
        isPlaying: Bool,
        duration: Double?,
        now: Date
    ) -> Double? {
        guard let elapsed = number(object["elapsed"]), elapsed.isFinite, elapsed >= 0 else {
            return nil
        }
        var position = elapsed
        if isPlaying,
           let rate = number(object["rate"]), rate.isFinite, rate > 0,
           let stamp = number(object["at"]), stamp.isFinite {
            position += max(0, now.timeIntervalSince1970 - stamp) * rate
        }
        if let duration {
            position = min(position, duration)
        }
        return position.isFinite ? max(0, position) : nil
    }

    // MARK: Values

    /// Letters, digits, `.`, `-` and `_` only, at most ``maxBundleLength`` characters.
    private static func isValidBundle(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maxBundleLength else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2E, 0x2D, 0x5F: true
            default: false
            }
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

    /// A length in seconds, when it is above 0 and at most a day.
    private static func duration(_ value: Any?) -> Double? {
        guard let seconds = number(value), seconds.isFinite, seconds > 0, seconds <= maxDuration else {
            return nil
        }
        return seconds
    }

    private static func playing(_ value: Any?) -> Bool {
        if let flag = value as? Bool {
            return flag
        }
        if let count = value as? Double {
            return count != 0
        }
        return false
    }

    /// `Int`, `Double`, `NSNumber` and a numeric `String` count as numbers; a Boolean does not.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : number.doubleValue
        default:
            return nil
        }
    }
}
