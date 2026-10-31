//
//  NowPlayingSource.swift
//  holzBar
//

import Foundation

/// The only place the Now Playing module touches the system: it listens to the distributed
/// playback notifications of Apple Music, which need no permission.
///
/// AppKit suspends distributed notifications for an app that is not active, which an accessory
/// app almost always is, unless they are registered with `.deliverImmediately`. The block-based
/// form of `addObserver` has no such parameter, so the selector-based one is used. Every
/// notification goes through ``NowPlayingPayload/parse(name:userInfo:)`` before it reaches the
/// handler, and the handler gets only an event that was understood.
@MainActor
final class NowPlayingSource: NSObject {
    private var handler: (@MainActor (NowPlayingEvent) -> Void)?

    /// Starts listening. A source that is already listening is restarted.
    func start(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void) {
        stop()
        self.handler = handler
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playbackDidChange(_:)),
            name: Notification.Name(NowPlayingPayload.musicNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    /// Removes every observer and lets go of the handler.
    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        handler = nil
    }

    /// The center delivers on the main thread. The payload is parsed here, where it is data of
    /// unknown shape; only the parsed event, which is a plain value, crosses into the handler.
    @objc nonisolated private func playbackDidChange(_ notification: Notification) {
        guard let event = NowPlayingPayload.parse(
            name: notification.name.rawValue,
            userInfo: notification.userInfo ?? [:]
        ) else {
            return
        }
        MainActor.assumeIsolated {
            handler?(event)
        }
    }
}
