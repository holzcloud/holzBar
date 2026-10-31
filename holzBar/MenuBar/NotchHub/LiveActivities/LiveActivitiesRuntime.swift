//
//  LiveActivitiesRuntime.swift
//  holzBar
//

import Foundation
import Observation
import SwiftUI

/// The running part of the Live activities module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It turns what its
/// sources report into ``LiveActivity`` values, which the hub shows as a capsule below the
/// notch while it is closed and as a list in this module's tab. It has two sources, each with
/// its own switch in ``LiveActivitiesSettings``: a camera or the microphone in use by another
/// app, from listeners that need no permission, and the downloads in progress in the Downloads
/// folder, which asks macOS for the folder when its switch is turned on. A source that is off
/// does not exist.
@MainActor
@Observable
final class LiveActivitiesRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "live-activities"

    let moduleID = LiveActivitiesRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// Since when a camera is in use, or `nil`.
    private(set) var cameraSince: Date?

    /// Since when the microphone is in use, or `nil`.
    private(set) var microphoneSince: Date?

    /// The downloads in progress and the ones just finished, as the Downloads source last
    /// reported them. File names live here in memory only.
    private(set) var downloads = DownloadTracker()

    /// Whether macOS lets holzBar read the Downloads folder; ``DownloadsSource/Access/unknown``
    /// while the Downloads source is off.
    private(set) var downloadsAccess = DownloadsSource.Access.unknown

    /// The camera and microphone source, while it runs. It is stored as `Any` because the type
    /// exists only on macOS 14.2 and later.
    @ObservationIgnored private var captureSource: Any?

    /// The Downloads source, while its switch is on.
    @ObservationIgnored private var downloadsSource: DownloadsSource?

    /// Follows the two switches of the sources.
    @ObservationIgnored private var switchesLoop: ObservationLoop?

    /// The two switches that decide which sources run.
    private struct Switches: Equatable {
        let capturesInUse: Bool
        let watchesDownloads: Bool
    }

    /// Starts the sources whose switches are on, and follows the switches. The camera and
    /// microphone listeners need no permission; the Downloads source asks macOS for the folder
    /// when its switch is on.
    init(appState: AppState) {
        let settings = appState.settings.liveActivities
        apply(Switches(capturesInUse: settings.capturesInUse, watchesDownloads: settings.watchesDownloads))
        switchesLoop = ObservationLoop.observe {
            Switches(capturesInUse: settings.capturesInUse, watchesDownloads: settings.watchesDownloads)
        } onChange: { [weak self] switches in
            self?.apply(switches)
        }
    }

    // MARK: Activities

    var activities: [LiveActivity] {
        var result = [LiveActivity]()
        if let since = cameraSince {
            result.append(
                LiveActivity(
                    id: "camera",
                    moduleID: moduleID,
                    kind: .capture,
                    symbol: "camera.fill",
                    title: String(localized: "Camera in use"),
                    priority: 20,
                    startedAt: since,
                    tint: .red
                )
            )
        }
        if let since = microphoneSince {
            result.append(
                LiveActivity(
                    id: "microphone",
                    moduleID: moduleID,
                    kind: .capture,
                    symbol: "mic.fill",
                    title: String(localized: "Microphone in use"),
                    priority: 20,
                    startedAt: since,
                    tint: .red
                )
            )
        }
        for item in downloads.running {
            result.append(
                LiveActivity(
                    id: "download-\(item.id)",
                    moduleID: moduleID,
                    kind: .download,
                    symbol: "arrow.down.circle",
                    title: String(localized: "Downloading"),
                    detail: item.name,
                    priority: 10,
                    startedAt: item.startedAt,
                    tint: .accent
                )
            )
        }
        for item in downloads.finished {
            result.append(
                LiveActivity(
                    id: "download-\(item.id)",
                    moduleID: moduleID,
                    kind: .download,
                    symbol: "checkmark.circle",
                    title: String(localized: "Download finished"),
                    detail: item.name,
                    priority: 10,
                    startedAt: item.startedAt,
                    finishedAt: item.finishedAt,
                    tint: .green
                )
            )
        }
        return result
    }

    // MARK: Hub

    /// The Overview card: the top activity, and how many more are live. Nothing while nothing
    /// is live.
    var tile: HubTile? {
        let board = HubActivityBoard.board(activities, now: .now)
        guard let top = board.compact else {
            return nil
        }
        let value = top.title.count > 14 ? String(top.title.prefix(13)) + "…" : top.title
        return HubTile(
            symbol: top.symbol,
            title: Text("Now"),
            value: value,
            detail: board.hiddenCount > 0 ? Text("+\(board.hiddenCount) more") : nil
        )
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(LiveActivitiesBodyView(runtime: self))
    }

    /// Stops the sources and lets go of what they reported.
    func shutDown() {
        switchesLoop?.cancel()
        switchesLoop = nil
        stopCapture()
        stopDownloads()
    }

    // MARK: Sources

    /// Starts and stops each source by its switch. A source already in the state asked for is
    /// left alone.
    private func apply(_ switches: Switches) {
        if switches.capturesInUse {
            if #available(macOS 14.2, *), captureSource == nil {
                startCapture()
            }
        } else {
            stopCapture()
        }
        if switches.watchesDownloads {
            if downloadsSource == nil {
                startDownloads()
            }
        } else {
            stopDownloads()
        }
    }

    // MARK: Downloads

    private func startDownloads() {
        let source = DownloadsSource()
        downloadsSource = source
        source.onChange = { [weak self, weak source] in
            guard let self, let source else {
                return
            }
            if downloads != source.tracker {
                downloads = source.tracker
            }
            if downloadsAccess != source.access {
                downloadsAccess = source.access
            }
        }
        source.start()
    }

    /// Stops the Downloads source and forgets every download, so no file name outlives it.
    private func stopDownloads() {
        downloadsSource?.stop()
        downloadsSource = nil
        // Assigned only when they change, so nothing observes a switch that was already off.
        if !downloads.isEmpty {
            downloads = DownloadTracker()
        }
        if downloadsAccess != .unknown {
            downloadsAccess = .unknown
        }
    }

    // MARK: Capture

    /// Stops the camera and microphone source and forgets what it reported.
    private func stopCapture() {
        if #available(macOS 14.2, *), let source = captureSource as? CaptureActivitySource {
            source.stop()
        }
        captureSource = nil
        if cameraSince != nil {
            cameraSince = nil
        }
        if microphoneSince != nil {
            microphoneSince = nil
        }
    }

    @available(macOS 14.2, *)
    private func startCapture() {
        let source = CaptureActivitySource()
        captureSource = source
        source.start { [weak self] isCameraInUse, isMicrophoneInUse in
            self?.captureDidChange(isCameraInUse: isCameraInUse, isMicrophoneInUse: isMicrophoneInUse)
        }
    }

    /// Stores what changed with the moment of the change; a state that did not change is not
    /// assigned, so nothing observes it.
    private func captureDidChange(isCameraInUse: Bool, isMicrophoneInUse: Bool) {
        let now = Date.now
        if isCameraInUse != (cameraSince != nil) {
            cameraSince = isCameraInUse ? now : nil
        }
        if isMicrophoneInUse != (microphoneSince != nil) {
            microphoneSince = isMicrophoneInUse ? now : nil
        }
    }
}
