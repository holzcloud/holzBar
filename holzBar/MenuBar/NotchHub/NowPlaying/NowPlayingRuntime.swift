//
//  NowPlayingRuntime.swift
//  holzBar
//

import Foundation
import Observation
import OSLog
import SwiftUI

/// The running part of the Now Playing module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off: no observer and no
/// event. What plays (title, artist, album, a file location) is held in this object, in memory
/// only; it is never logged, written or sent, and ``shutDown()`` drops it.
@MainActor
@Observable
final class NowPlayingRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "now-playing"

    let moduleID = NowPlayingRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// The latest playback event that was understood.
    private(set) var event: NowPlayingEvent?

    @ObservationIgnored private let source = NowPlayingSource()
    @ObservationIgnored private let logger = Logger(category: "NowPlaying")

    init(appState: AppState) {
        source.start { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NowPlayingEvent) {
        self.event = event
        // Counts and states only: a title, an artist or a path is never logged.
        logger.debug("A playback event arrived")
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(NowPlayingBodyView(runtime: self))
    }

    /// Stops listening and lets go of what played.
    func shutDown() {
        source.stop()
        event = nil
    }
}
