//
//  Notify.swift
//  now-playing
//

import Foundation
import NowPlayingProbeCore

/// Listens to the distributed notifications of Apple Music and Spotify and writes one NOTIFY
/// line per event: the key names and value types, which facts are present, and the player state.
/// It prints no track text unless `--show-values` is given. It writes no file and opens no
/// network connection.
@MainActor
final class NotifyListener: NSObject {
    private enum Player {
        case music, spotify
    }

    /// The three names the probe watches. The iTunes name is the legacy name of Music's.
    private static let watched: [String: Player] = [
        "com.apple.Music.playerInfo": .music,
        "com.apple.iTunes.playerInfo": .music,
        "com.spotify.client.PlaybackStateChanged": .spotify,
    ]

    /// A name that contains one of these words (lowercase) is player-like.
    private static let playerWords = ["player", "playback", "nowplaying", "track", "media"]

    private let session: Session
    private var count = 0
    private var music = PlayerObservation()
    private var spotify = PlayerObservation()
    private var otherNames: Set<String> = []
    /// How many notifications the observer without a name delivered, of any name: a run with
    /// zero says that the list of OTHER names is empty because nothing reached the observer, not
    /// because no other player exists.
    private var anyCount = 0

    init(session: Session) {
        self.session = session
        super.init()
    }

    /// Registers for the three names and for all names, to be delivered immediately: AppKit
    /// suspends distributed notifications for an app that is not active unless they are
    /// registered this way, which is the state of an accessory app such as holzBar. The
    /// selector-based form is used because the block-based one has no suspension parameter.
    func start() {
        let center = DistributedNotificationCenter.default()
        for name in Self.watched.keys.sorted() {
            center.addObserver(
                self, selector: #selector(playerEvent(_:)), name: Notification.Name(name),
                object: nil, suspensionBehavior: .deliverImmediately
            )
        }
        center.addObserver(
            self, selector: #selector(anyEvent(_:)), name: nil,
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func playerEvent(_ notification: Notification) {
        let name = notification.name.rawValue
        guard let player = Self.watched[name] else { return }
        count += 1
        let userInfo = Self.plain(notification.userInfo)
        let inventory = PayloadInventory.inventory(userInfo)
        let flags = PayloadInventory.flags(inventory)
        switch player {
        case .music: music.record(flags)
        case .spotify: spotify.record(flags)
        }
        Output.emit("NOTIFY", [
            ("n", String(count)),
            ("name", name),
            ("t", session.elapsed()),
            ("state", PayloadInventory.state(in: userInfo)),
            ("keys", PayloadInventory.describe(inventory)),
            ("has", flags.has),
        ])
        if session.options.showValues {
            for entry in inventory {
                let text = String(describing: userInfo[entry.key] ?? "").replacingOccurrences(of: "\n", with: " ")
                Output.emit("VALUE", [("n", String(count)), ("key", entry.key), ("value", text)])
            }
        }
    }

    @objc private func anyEvent(_ notification: Notification) {
        anyCount += 1
        let name = notification.name.rawValue
        guard Self.watched[name] == nil, !otherNames.contains(name) else { return }
        let lowercase = name.lowercased()
        guard Self.playerWords.contains(where: { lowercase.contains($0) }) else { return }
        otherNames.insert(name)
        Output.emit("OTHER", [("name", name)])
    }

    private static func plain(_ userInfo: [AnyHashable: Any]?) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in userInfo ?? [:] {
            if let key = key as? String { result[key] = value }
        }
        return result
    }

    /// Runs the whole `notify` command: STEP lines, the run loop, SUMMARY, the questions.
    static func run(session: Session) {
        let listener = NotifyListener(session: session)
        listener.start()
        session.step("In Apple Music: play a song, pause, resume, skip to the next song, then seek inside a song.")
        session.step("In Spotify: do the same. Leave each state for a few seconds.")
        session.step("The run ends after \(session.options.seconds) seconds or with Ctrl-C and still writes the report.")
        runMainLoop(seconds: session.options.seconds)
        listener.stop()
        session.step("The observer without a name delivered \(listener.anyCount) notifications of any name.")

        let source = Verdict.source(
            music: listener.music.events > 0 ? listener.music : nil,
            spotify: listener.spotify.events > 0 ? listener.spotify : nil
        )
        Output.emit(Verdict.summaryLine(
            music: listener.music, spotify: listener.spotify, others: listener.otherNames.count,
            source: source, controls: nil, remote: nil
        ))

        func answers(_ what: String) -> String {
            let parts = [("music", "Apple Music"), ("spotify", "Spotify")].map { key, title -> String in
                let result = session.ask("Did a NOTIFY line appear when you \(what) in \(title)?")
                return "\(key):\(result.map { $0 ? "y" : "n" } ?? "-")"
            }
            return parts.joined(separator: ";")
        }
        session.answer(
            playEvent: answers("pressed play"), pauseEvent: answers("paused"),
            skipEvent: answers("skipped to the next song"), seekEvent: answers("sought inside a song")
        )
        session.end()
    }
}
