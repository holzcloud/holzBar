//
//  NowPlayingRuntime.swift
//  holzBar
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// Where the current song is, as the values the system needs to draw the progress itself.
struct NowPlayingProgress: Equatable {
    /// The seconds played at the moment of the last event.
    let position: Double
    /// The length of the song, if known.
    let duration: Double?
    /// Whether the song plays; a paused song does not move.
    let isPlaying: Bool
    /// The date the song would have started at, so that `start + position` is the moment of the
    /// last event. It is fixed when an event arrives, not when the view is drawn.
    let start: Date

    /// The moment a playing song ends, if its length is known.
    var end: Date? {
        duration.map { start.addingTimeInterval($0) }
    }
}

/// The running part of the Now Playing module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off: no observer and no
/// event. What plays (title, artist, album, a file location) is held in this object, in memory
/// only; it is never logged, written or sent, and ``shutDown()`` drops it.
///
/// The module owns no timer and no wait. The elapsed time and the progress bar are drawn by the
/// system from a start and an end date (``NowPlayingProgress``), which are recomputed only when
/// an event arrives. Its only task is the one-shot read of a local song's artwork, off the main
/// actor; the buttons press the media keys through holzBar's existing poster, and only on a click.
@MainActor
@Observable
final class NowPlayingRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "now-playing"

    let moduleID = NowPlayingRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// Every known player and its state.
    private(set) var model = NowPlayingModel()

    /// The progress of the current player's song, or `nil` when nothing plays or is paused.
    private(set) var progress: NowPlayingProgress?

    /// Counts the events, so a view can start its progress over on each one.
    private(set) var revision = 0

    /// The artwork of the current song, when it is a local file that has one.
    private(set) var artwork: NSImage?

    @ObservationIgnored private let source = NowPlayingSource()
    @ObservationIgnored private let actions = BuiltInItemActions()
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkIdentity: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var players = NowPlayingPlayers.all
    @ObservationIgnored private var playersLoop: ObservationLoop?
    @ObservationIgnored private let logger = Logger(category: "NowPlaying")

    init(appState: AppState) {
        self.appState = appState
        let settings = appState.settings.nowPlaying
        players = settings.players
        startSource()
        playersLoop = ObservationLoop.observe {
            settings.players
        } onChange: { [weak self] players in
            self?.playersDidChange(players)
        }
    }

    private func startSource() {
        source.start(players: players) { [weak self] event in
            self?.handle(event)
        } onPlayerQuit: { [weak self] player in
            self?.playerDidQuit(player)
        }
    }

    /// The setting changed: observe only the chosen players' notifications and drop the state of
    /// a player that was switched off.
    private func playersDidChange(_ players: NowPlayingPlayers) {
        self.players = players
        startSource()
        for player in [NowPlayingPlayer.music, .spotify] where !players.allows(player) {
            model.clear(player)
        }
        refresh()
    }

    // MARK: Events

    private func handle(_ event: NowPlayingEvent) {
        // A player the user switched off is ignored, whichever way its event arrived.
        guard players.allows(event.player) else {
            return
        }
        let before = current?.event.track?.identity
        model.handle(event, at: ProcessInfo.processInfo.systemUptime)
        refresh()
        if current?.event.track?.identity != before {
            // Counts only: a title, an artist or a path is never logged.
            logger.debug("A track changed: \(self.model.players.count, privacy: .public) players known")
        }
    }

    private func playerDidQuit(_ player: NowPlayingPlayer) {
        model.clear(player)
        refresh()
    }

    /// Recomputes what the views draw from, after the model changed.
    private func refresh() {
        revision += 1
        guard let current, current.event.state != .stopped else {
            progress = nil
            clearArtwork()
            return
        }
        updateArtwork(for: current.event.track)
        let position = model.position(of: current.player, at: ProcessInfo.processInfo.systemUptime) ?? 0
        progress = NowPlayingProgress(
            position: position,
            duration: current.event.track?.duration,
            isPlaying: current.event.state == .playing,
            start: Date.now.addingTimeInterval(-position)
        )
    }

    // MARK: Controls

    /// Presses a media key. Only the buttons of the tab call it, so a key is posted only on a
    /// click; whatever app macOS treats as the now-playing app answers.
    func send(_ key: MediaKey) {
        actions.press(key)
    }

    /// Whether the buttons work: posting a key needs holzBar's Accessibility grant, which is
    /// observable, so the buttons enable and disable themselves when the grant changes.
    var canControl: Bool {
        appState?.permissions.accessibility.hasPermission ?? false
    }

    // MARK: Artwork

    /// Starts the one-shot read when the song changed; the picture is for the current song only.
    private func updateArtwork(for track: NowPlayingTrack?) {
        let identity = track?.identity
        guard identity != artworkIdentity else {
            return
        }
        clearArtwork()
        artworkIdentity = identity
        guard let fileURL = track?.fileURL else {
            return
        }
        generation += 1
        let wanted = generation
        artworkTask = Task { [weak self] in
            let data = await NowPlayingArtworkReader.thumbnail(for: fileURL)
            guard !Task.isCancelled, let self, wanted == generation else {
                return
            }
            artwork = data.flatMap { NSImage(data: $0) }
        }
    }

    /// Cancels the read and lets go of the picture.
    private func clearArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkIdentity = nil
        generation += 1
        artwork = nil
    }

    /// The player the hub shows and its latest event.
    var current: (player: NowPlayingPlayer, event: NowPlayingEvent)? {
        model.current
    }

    // MARK: Hub

    /// The Overview card: the state and the title of what plays, or a sentence when nothing does.
    var tile: HubTile? {
        guard let event = current?.event, event.state != .stopped else {
            return HubTile(
                symbol: "music.note",
                title: Text("Now Playing"),
                value: String(localized: "Nothing is playing")
            )
        }
        let title = event.track?.title ?? String(localized: "Unknown title")
        let value = title.count > 14 ? String(title.prefix(13)) + "…" : title
        return HubTile(
            symbol: "music.note",
            title: event.state == .playing ? Text("Playing") : Text("Paused"),
            value: value,
            detail: event.track?.artist.map { Text(verbatim: $0) }
        )
    }

    /// The right wing's pill: the title, only while a song plays.
    var statusPill: HubStatusPill? {
        guard let event = current?.event, event.state == .playing else {
            return nil
        }
        let title = event.track?.title ?? String(localized: "Unknown title")
        let text = title.count > 18 ? String(title.prefix(17)) + "…" : title
        return HubStatusPill(
            symbol: "music.note",
            text: text,
            accessibilityLabel: Text("Now playing: \(title)")
        )
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(NowPlayingBodyView(runtime: self))
    }

    /// Stops listening and lets go of what played.
    func shutDown() {
        playersLoop?.cancel()
        playersLoop = nil
        source.stop()
        clearArtwork()
        model.removeAll()
        progress = nil
    }
}
