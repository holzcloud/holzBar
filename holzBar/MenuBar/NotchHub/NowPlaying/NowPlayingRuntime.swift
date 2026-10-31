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
/// an event arrives. Its only tasks are the one-shot read of a local song's artwork, off the main
/// actor, and, while Read all apps is on and the hub is open, the reading of the helper's output
/// in ``MediaRemoteBridge``; the buttons press the media keys through holzBar's existing poster,
/// and only on a click.
///
/// Read all apps (the optional private route) exists only while its switch is on, the hub is
/// open and ``remoteGate`` is available: the runtime starts the bridge when the hub opens and
/// ends it when the hub closes, when the switch goes off and on shutdown. Apps other than Music
/// and Spotify that it reports show like the public players; Music and Spotify from it are
/// ignored, because the public notifications and the players setting own them. When the
/// interface or the helper fails, the gate switches the route off for the session and the module
/// says so; the public sources keep working.
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

    /// Whether Read all apps may run: its switch, and what loading and running the helper gave.
    /// Switched off by itself for the session after a missing interface or three failures.
    private(set) var remoteGate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    @ObservationIgnored private let bridge = MediaRemoteBridge()
    @ObservationIgnored private var readsAllApps = false
    @ObservationIgnored private var hubIsOpen = false
    @ObservationIgnored private var remotePlayers = Set<NowPlayingPlayer>()
    @ObservationIgnored private var readsAllAppsLoop: ObservationLoop?

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
        readsAllApps = settings.readsAllApps
        remoteGate = PrivateFeatureGate(isEnabled: readsAllApps, load: .loaded)
        bridge.onLine = { [weak self] line in
            self?.remoteLineArrived(line)
        }
        bridge.onExit = { [weak self] status in
            self?.remoteDidExit(status: status)
        }
        bridge.onUnusable = { [weak self] in
            self?.remoteIsUnusable()
        }
        readsAllAppsLoop = ObservationLoop.observe {
            settings.readsAllApps
        } onChange: { [weak self] isOn in
            self?.readsAllAppsDidChange(isOn)
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
        // Artwork comes from a local file named by Music; the route that reads all apps names none.
        updateArtwork(for: current.player.hasPublicSource ? current.event.track : nil)
        let position = model.position(of: current.player, at: ProcessInfo.processInfo.systemUptime) ?? 0
        progress = NowPlayingProgress(
            position: position,
            duration: current.event.track?.duration,
            isPlaying: current.event.state == .playing,
            start: Date.now.addingTimeInterval(-position)
        )
    }

    // MARK: Read all apps

    /// Whether the module says that Read all apps switched itself off: the user wants it, and
    /// the gate does not allow it.
    var showsRemoteUnavailable: Bool {
        if case .unavailable(let reason) = remoteGate.state, reason != .switchedOff {
            return true
        }
        return false
    }

    /// The name of an app the route reported: the running app's name, else the last part of its
    /// bundle identifier. Held in memory only, never logged.
    func appName(for player: NowPlayingPlayer) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier)
            .first?.localizedName
            ?? player.bundleIdentifier.split(separator: ".").last.map(String.init)
            ?? player.bundleIdentifier
    }

    /// The switch changed: start afresh with an empty count of failures.
    private func readsAllAppsDidChange(_ isOn: Bool) {
        readsAllApps = isOn
        stopRemote()
        remoteGate.setEnabled(isOn, load: .loaded)
        appState?.settings.nowPlaying.remoteIsUnavailable = false
        startRemote()
    }

    /// Starts the route, only while the switch is on, the hub is open and the gate allows it.
    private func startRemote() {
        guard hubIsOpen, PrivateFeatureGate.shouldLoad(isEnabled: readsAllApps), remoteGate.isAvailable,
              !bridge.isActive else {
            return
        }
        bridge.start()
    }

    /// Ends the route and drops the players it reported.
    private func stopRemote() {
        bridge.stop()
        removeRemotePlayers()
    }

    private func removeRemotePlayers() {
        guard !remotePlayers.isEmpty else {
            return
        }
        for player in remotePlayers {
            model.clear(player)
        }
        remotePlayers.removeAll()
        refresh()
    }

    /// One line of the helper's output. Every line goes through the parser first.
    private func remoteLineArrived(_ line: String) {
        switch NowPlayingRemoteMessage.parse(line: line, now: .now) {
        case .event(let event):
            remoteGate.recordSuccess()
            // Music and Spotify belong to the public notifications and the players setting.
            guard !event.player.hasPublicSource else {
                return
            }
            remotePlayers.insert(event.player)
            handle(event)
        case .none:
            remoteGate.recordSuccess()
            removeRemotePlayers()
        case .unavailable(let failure):
            switch failure {
            case .framework: remoteGate = PrivateFeatureGate(isEnabled: true, load: .frameworkMissing)
            case .symbol: remoteGate = PrivateFeatureGate(isEnabled: true, load: .symbolMissing)
            case .unavailable, .timeout: remoteGate.recordFailure()
            }
            remoteGateDidChange()
        case .invalid:
            remoteGate.recordFailure()
            remoteGateDidChange()
        }
    }

    /// The helper ended by itself. Exit codes 3 and 4 are perl's: the library did not load or the
    /// function was missing. 5 and 6 follow an error line that was already counted. Anything
    /// else is a failure. The route starts again at once while the gate allows it.
    private func remoteDidExit(status: Int32) {
        switch status {
        case 3: remoteGate = PrivateFeatureGate(isEnabled: true, load: .frameworkMissing)
        case 4: remoteGate = PrivateFeatureGate(isEnabled: true, load: .symbolMissing)
        case 5, 6: break
        default: remoteGate.recordFailure()
        }
        removeRemotePlayers()
        remoteGateDidChange()
        startRemote()
    }

    /// The bundle failed its check, the helper is missing, the process could not start or a line
    /// was too long: the part is not available.
    private func remoteIsUnusable() {
        remoteGate = PrivateFeatureGate(isEnabled: true, load: .frameworkMissing)
        remoteGateDidChange()
    }

    /// Switches the route off for the session when the gate says so, and tells the settings.
    private func remoteGateDidChange() {
        guard !remoteGate.isAvailable else {
            return
        }
        stopRemote()
        guard let settings = appState?.settings.nowPlaying, !settings.remoteIsUnavailable else {
            return
        }
        settings.remoteIsUnavailable = true
        // Once: names of apps and songs are never logged.
        logger.notice("Read all apps switched itself off for this session")
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

    /// The route that reads all apps runs only while the hub is open.
    func hubVisibilityDidChange(isOpen: Bool) {
        hubIsOpen = isOpen
        if isOpen {
            startRemote()
        } else {
            stopRemote()
        }
    }

    /// Stops listening and lets go of what played.
    func shutDown() {
        playersLoop?.cancel()
        playersLoop = nil
        readsAllAppsLoop?.cancel()
        readsAllAppsLoop = nil
        hubIsOpen = false
        stopRemote()
        bridge.onLine = nil
        bridge.onExit = nil
        bridge.onUnusable = nil
        appState?.settings.nowPlaying.remoteIsUnavailable = false
        source.stop()
        clearArtwork()
        model.removeAll()
        progress = nil
    }
}
