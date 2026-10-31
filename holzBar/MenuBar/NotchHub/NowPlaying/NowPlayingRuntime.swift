//
//  NowPlayingRuntime.swift
//  holzBar
//

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
/// an event arrives.
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

    @ObservationIgnored private let source = NowPlayingSource()
    @ObservationIgnored private let logger = Logger(category: "NowPlaying")

    init(appState: AppState) {
        source.start { [weak self] event in
            self?.handle(event)
        } onPlayerQuit: { [weak self] player in
            self?.playerDidQuit(player)
        }
    }

    // MARK: Events

    private func handle(_ event: NowPlayingEvent) {
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
            return
        }
        let position = model.position(of: current.player, at: ProcessInfo.processInfo.systemUptime) ?? 0
        progress = NowPlayingProgress(
            position: position,
            duration: current.event.track?.duration,
            isPlaying: current.event.state == .playing,
            start: Date.now.addingTimeInterval(-position)
        )
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
        source.stop()
        model.removeAll()
        progress = nil
    }
}
