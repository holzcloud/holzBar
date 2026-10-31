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
/// notch while it is closed and as a list in this module's tab. The only source so far is a
/// camera or the microphone in use by another app, from listeners that need no permission.
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

    /// The camera and microphone source, while it runs. It is stored as `Any` because the type
    /// exists only on macOS 14.2 and later.
    @ObservationIgnored private var captureSource: Any?

    /// Starts the sources. Nothing is asked of the user: the listeners need no permission.
    init(appState: AppState) {
        if #available(macOS 14.2, *) {
            startCapture()
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
        if #available(macOS 14.2, *), let source = captureSource as? CaptureActivitySource {
            source.stop()
        }
        captureSource = nil
        cameraSince = nil
        microphoneSince = nil
    }

    // MARK: Capture

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
