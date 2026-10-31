//
//  Verdict.swift
//  now-playing
//

import Foundation

/// What the probe saw of one player over a run: how many notifications, and the facts any of
/// them carried.
public struct PlayerObservation: Sendable, Equatable {
    public private(set) var events = 0
    public private(set) var flags = PayloadInventory.Flags()

    public init() {}

    public mutating func record(_ eventFlags: PayloadInventory.Flags) {
        events += 1
        flags = flags.merged(with: eventFlags)
    }

    /// Whether the player's notifications carried a title and a state, the least the module needs.
    var works: Bool { events > 0 && flags.hasName && flags.hasState }

    /// Whether they carried everything the GO criterion names.
    var isComplete: Bool { works && flags.hasArtist && flags.hasDuration }
}

/// One look at MediaRemote: through which route, how many keys the dictionary had, which app it
/// named, and what the maintainer said was playing.
public struct RemoteObservation: Sendable, Equatable {
    public let route: String
    public let keys: Int
    public let app: String?
    public let label: String?

    public init(route: String, keys: Int, app: String?, label: String?) {
        self.route = route
        self.keys = keys
        self.app = app
        self.label = label
    }

    /// Reads a MEDIAREMOTE line; any other line is nil. A result other than `keys:N` counts as no keys.
    public static func parse(line: String, label: String? = nil) -> RemoteObservation? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.first == "MEDIAREMOTE" else { return nil }
        var values: [String: String] = [:]
        for field in fields.dropFirst() {
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        guard let route = values["route"] else { return nil }
        var keys = 0
        if let result = values["result"], result.hasPrefix("keys:"), let count = Int(result.dropFirst(5)) {
            keys = count
        }
        let app = values["app"].flatMap { $0 == "-" || $0.isEmpty ? nil : $0 }
        return RemoteObservation(route: route, keys: keys, app: app, label: label)
    }
}

/// The three results of the spike, as pure functions of the observations, by the criteria fixed
/// in 38-CONTEXT.md before any run (2026-10-16; changed once, 2026-10-29, also before any run).
public enum Verdict {
    public enum Result: String, Sendable {
        case go = "GO"
        case reducedGo = "REDUCED-GO"
        case noGo = "NO-GO"
    }

    public static let musicBundleIdentifier = "com.apple.Music"
    public static let spotifyBundleIdentifier = "com.spotify.client"

    /// The labels of `--playing` that say an app other than Music and Spotify played.
    static let otherAppLabels: Set<String> = ["browser", "video", "other"]

    /// SOURCE. GO: both players carry a name, an artist, a duration and a state. REDUCED-GO:
    /// only one works, or a working player lacks the duration. NO-GO: neither works.
    public static func source(music: PlayerObservation?, spotify: PlayerObservation?) -> Result {
        let players = [music, spotify].compactMap { $0 }
        if players.count == 2, players.allSatisfy(\.isComplete) { return .go }
        if players.contains(where: \.works) { return .reducedGo }
        return .noGo
    }

    /// CONTROLS. Each argument is nil when that player's key was not run.
    public static func controls(musicToggled: Bool?, spotifyToggled: Bool?) -> Result {
        let toggled = [musicToggled, spotifyToggled].filter { $0 == true }.count
        switch toggled {
        case 2: return .go
        case 1: return .reducedGo
        default: return .noGo
        }
    }

    public static func controlsReason(musicToggled: Bool?, spotifyToggled: Bool?) -> String {
        if musicToggled == nil, spotifyToggled == nil { return "not run" }
        if musicToggled == true || spotifyToggled == true { return "a key toggled playback" }
        return "no key toggled playback"
    }

    /// REMOTE. Only observations of the perl route count. GO: keys from an app that is neither
    /// Music nor Spotify, or from an unknown app while the maintainer said a browser, a video
    /// app or another app played. REDUCED-GO: keys, but nothing qualifies for GO. NO-GO: no keys.
    public static func remote(_ observations: [RemoteObservation]) -> Result {
        let withKeys = observations.filter { $0.route == "perl" && $0.keys > 0 }
        guard !withKeys.isEmpty else { return .noGo }
        let qualifies = withKeys.contains { observation in
            if let app = observation.app {
                return app != musicBundleIdentifier && app != spotifyBundleIdentifier
            }
            return observation.label.map { otherAppLabels.contains($0) } ?? false
        }
        return qualifies ? .go : .reducedGo
    }

    /// The SUMMARY line, in the output contract's key order; `-` for what was not observed.
    public static func summaryLine(
        music: PlayerObservation?, spotify: PlayerObservation?, others: Int,
        source: Result?, controls: Result?, remote: Result?
    ) -> String {
        func flag(_ observation: PlayerObservation?, _ value: KeyPath<PayloadInventory.Flags, Bool>) -> String? {
            guard let observation, observation.events > 0 else { return nil }
            return observation.flags[keyPath: value] ? "y" : "n"
        }
        return ReportLine.format(tag: "SUMMARY", [
            ("music", String(music?.events ?? 0)),
            ("spotify", String(spotify?.events ?? 0)),
            ("others", String(others)),
            ("musicPosition", flag(music, \.hasPosition)),
            ("spotifyPosition", flag(spotify, \.hasPosition)),
            ("musicLocation", flag(music, \.hasLocation)),
            ("source", source?.rawValue),
            ("controls", controls?.rawValue),
            ("remote", remote?.rawValue),
        ])
    }
}

/// The report format of the probe: `TAG key=value ...` in the order the caller gives, a value
/// with a space, a tab or a quote quoted, an unknown value written as `-`.
public enum ReportLine {
    public static func format(tag: String, _ pairs: [(String, String?)]) -> String {
        let parts = pairs.map { key, value in "\(key)=\(render(value))" }
        return ([tag] + parts).joined(separator: " ")
    }

    private static func render(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.contains(where: { $0 == " " || $0 == "\"" || $0 == "\t" }) else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
