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
/// through ``NotificationLog``, with the exclusion list and whether the screen is mirrored or
/// shared. The list lives in this object and nowhere else: it is not written, exported or sent,
/// it holds at most twenty notifications, and Remove, Clear all and ``shutDown()`` erase it.
/// Nothing here logs an app, a title or a text, and the Overview's tile and the pill show a
/// count only.
@MainActor
@Observable
final class NotificationsRuntime: HubModuleRuntime {
    let moduleID = "notifications"
    let tint = HubTint.accent
    let offersTab = true

    /// The notifications, newest first.
    private(set) var log = NotificationLog()

    /// How many notifications were recorded since the tab was last shown.
    private(set) var unread = 0

    @ObservationIgnored private let reader = NotificationBannerReader()
    @ObservationIgnored private var permissionLoop: ObservationLoop?
    @ObservationIgnored private weak var appState: AppState?

    /// Starts reading. The reader says by its state when Accessibility is off.
    init(appState: AppState) {
        self.appState = appState
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

    /// What the reader is doing, for the tab to say why nothing is read.
    var readerState: NotificationBannerReader.State {
        reader.state
    }

    // MARK: Recording

    private func snapshotDidArrive(_ snapshot: AXSnapshot) {
        guard let draft = NotificationBannerParser.parse(snapshot) else {
            // Not a banner holzBar knows: dropped, never guessed at.
            return
        }
        let excluded = Set(appState?.settings.notifications.excludedApps ?? [])
        let outcome = log.record(
            draft,
            now: .now,
            excludedApps: excluded,
            isPresenting: Self.isScreenPresented(),
            makeID: UUID.init
        )
        if outcome == .recorded {
            unread = min(unread + 1, log.records.count)
        }
    }

    /// Whether the screen is mirrored or shared, read once per banner exactly as
    /// `PresentationMonitor` reads it.
    private static func isScreenPresented() -> Bool {
        PresentationSignals.isPresenting(
            mirroredDisplays: PresentationMonitor.mirroredDisplayCount(),
            runningBundleIDs: PresentationMonitor.runningBundleIDs()
        )
    }

    // MARK: Actions

    /// Marks everything recorded so far as seen. The tab calls it when it appears and while it is
    /// shown.
    func markSeen() {
        if unread != 0 {
            unread = 0
        }
    }

    /// Erases one notification at once.
    func remove(_ id: NotificationRecord.ID) {
        log.remove(id)
        unread = min(unread, log.records.count)
    }

    /// Erases every notification at once.
    func removeAll() {
        log.removeAll()
        unread = 0
    }

    /// Never shows notifications from the app again, and erases the ones already listed.
    func exclude(app: String) {
        appState?.settings.notifications.exclude(app)
        log.removeAll(fromApp: app)
        unread = min(unread, log.records.count)
    }

    // MARK: Hub

    /// The Overview card: how many notifications are listed, nothing else.
    var tile: HubTile? {
        guard !log.records.isEmpty else {
            return nil
        }
        return HubTile(symbol: "bell.badge", title: Text("Notifications"), value: String(log.records.count))
    }

    /// The right wing's pill: how many are new, nothing else.
    var statusPill: HubStatusPill? {
        guard unread > 0 else {
            return nil
        }
        return HubStatusPill(
            symbol: "bell.badge.fill",
            text: String(unread),
            accessibilityLabel: Text("\(unread) new notifications")
        )
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(NotificationsBodyView(runtime: self))
    }

    /// Stops the reader and erases the list.
    func shutDown() {
        permissionLoop?.cancel()
        permissionLoop = nil
        reader.stop()
        log = NotificationLog()
        unread = 0
    }
}
