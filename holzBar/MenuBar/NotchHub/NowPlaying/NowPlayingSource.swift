//
//  NowPlayingSource.swift
//  holzBar
//

import AppKit
import Foundation

/// The only place the Now Playing module touches the system: it listens to the distributed
/// playback notifications of Apple Music and Spotify, which need no permission, and to the
/// termination of apps, so that a player that quits disappears.
///
/// AppKit suspends distributed notifications for an app that is not active, which an accessory
/// app almost always is, unless they are registered with `.deliverImmediately`. The block-based
/// form of `addObserver` has no such parameter, so the selector-based one is used. Every
/// notification goes through ``NowPlayingPayload/parse(name:userInfo:)`` before it reaches the
/// handler, and the handler gets only an event that was understood.
@MainActor
final class NowPlayingSource: NSObject {
    private var onEvent: (@MainActor (NowPlayingEvent) -> Void)?
    private var onPlayerQuit: (@MainActor (NowPlayingPlayer) -> Void)?

    /// Starts listening. A source that is already listening is restarted.
    ///
    /// - Parameters:
    ///   - onEvent: Called with every playback event that was understood.
    ///   - onPlayerQuit: Called when Apple Music or Spotify quits.
    func start(
        onEvent: @escaping @MainActor (NowPlayingEvent) -> Void,
        onPlayerQuit: @escaping @MainActor (NowPlayingPlayer) -> Void
    ) {
        stop()
        self.onEvent = onEvent
        self.onPlayerQuit = onPlayerQuit
        let center = DistributedNotificationCenter.default()
        for name in [NowPlayingPayload.musicNotification, NowPlayingPayload.spotifyNotification] {
            center.addObserver(
                self,
                selector: #selector(playbackDidChange(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    /// Removes every observer and lets go of the handlers.
    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onEvent = nil
        onPlayerQuit = nil
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
            onEvent?(event)
        }
    }

    /// Reads only the bundle identifier of the app that quit, and keeps no reference to it.
    @objc nonisolated private func applicationDidTerminate(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let identifier = app?.bundleIdentifier else {
            return
        }
        let player = NowPlayingPlayer(bundleIdentifier: identifier)
        guard player == .music || player == .spotify else {
            return
        }
        MainActor.assumeIsolated {
            onPlayerQuit?(player)
        }
    }
}
