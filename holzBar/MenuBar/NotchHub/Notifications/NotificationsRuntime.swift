//
//  NotificationsRuntime.swift
//  holzBar
//

import Foundation
import Observation
import SwiftUI

/// The running part of the Notifications module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off: no observer, no task
/// and no record. It owns one ``NotificationBannerReader``; every snapshot the reader delivers
/// goes through ``NotificationBannerParser/parse(_:rules:)``, and a draft becomes a record only
/// through ``NotificationLog``. The list lives in this object and nowhere else: it is not
/// written, exported or sent, it holds at most twenty notifications, and ``shutDown()`` empties
/// it. Nothing here logs an app, a title or a text.
@MainActor
@Observable
final class NotificationsRuntime: HubModuleRuntime {
    let moduleID = "notifications"
    let tint = HubTint.accent
    let offersTab = true

    /// The notifications, newest first.
    private(set) var log = NotificationLog()

    @ObservationIgnored private let reader = NotificationBannerReader()
    @ObservationIgnored private var permissionLoop: ObservationLoop?

    /// Starts reading. The reader says by its state when Accessibility is off.
    init(appState: AppState) {
        let permission = appState.permissions.accessibility
        permissionLoop = ObservationLoop.observe {
            permission.hasPermission
        } onChange: { [weak self] _ in
            self?.reader.permissionDidChange()
        }
        reader.start { [weak self] snapshot in
            self?.snapshotDidArrive(snapshot)
        }
    }

    /// Why the module is not reading, or `nil` while it reads.
    var readerState: NotificationBannerReader.State {
        reader.state
    }

    private func snapshotDidArrive(_ snapshot: AXSnapshot) {
        guard let draft = NotificationBannerParser.parse(snapshot) else {
            // Not a banner holzBar knows: dropped, never guessed at.
            return
        }
        log.record(draft, now: .now, excludedApps: [], isPresenting: false, makeID: UUID.init)
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(NotificationsBodyView(runtime: self))
    }

    /// Stops the reader and empties the list.
    func shutDown() {
        permissionLoop?.cancel()
        permissionLoop = nil
        reader.stop()
        log = NotificationLog()
    }
}
