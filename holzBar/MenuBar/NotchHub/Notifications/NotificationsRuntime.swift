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
/// Nothing here logs an app, a title or a text, and the Overview's tile shows a count
/// only.
///
/// ``queue`` keeps the identifiers of the notifications not seen yet. While there are any, the
/// closed notch shows their count for the display time (``activities``): a bell and a number, never
/// a title, an app or a text. The count adds no observer of its own, because the reader above
/// already runs while the hub is on.
@MainActor
@Observable
final class NotificationsRuntime: HubModuleRuntime {
    let moduleID = "notifications"
    let tint = HubTint.accent
    let offersTab = true

    /// The notifications, newest first.
    private(set) var log = NotificationLog()

    /// The notifications not seen yet, as identifiers and instants only.
    private(set) var queue = NotificationQueue()

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
        let now = Date.now
        let outcome = log.record(
            draft,
            now: now,
            excludedApps: excluded,
            isPresenting: Self.isScreenPresented(),
            makeID: UUID.init
        )
        if outcome == .recorded, let newest = log.records.first {
            queue.arrived(newest.id, at: now)
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

    /// Erases one notification at once.
    func remove(_ id: NotificationRecord.ID) {
        log.remove(id)
        queue.forget(id)
    }

    /// Erases every notification at once.
    func removeAll() {
        log.removeAll()
        queue.markAllSeen()
    }

    /// Never shows notifications from the app again, and erases the ones already listed.
    func exclude(app: String) {
        appState?.settings.notifications.exclude(app)
        log.removeAll(fromApp: app)
        // The log decided which records the app's name matched; whatever it no longer holds is
        // not unseen any more.
        let kept = Set(log.records.map(\.id))
        for id in queue.unseen where !kept.contains(id) {
            queue.forget(id)
        }
    }

    /// The Notifications tab went away or the hub closed: everything listed counts as seen.
    func tabDidDisappear() {
        guard !queue.unseen.isEmpty else {
            return
        }
        queue.markAllSeen()
    }

    // MARK: Hub

    /// The Overview card: how many notifications are listed, nothing else.
    var tile: HubTile? {
        guard !log.records.isEmpty else {
            return nil
        }
        return HubTile(symbol: "bell.badge", title: Text("Notifications"), value: String(log.records.count))
    }

    /// The count of unseen notifications while there are any: one activity that is finished at the
    /// last arrival and held for the display time, so the hub drops it exactly then, and a new
    /// arrival restarts it with the new count. It carries a bell and a number and a fixed sentence
    /// for VoiceOver, never the title, the app or the text of a notification (D-17). It is no
    /// flash, so it does not fall back on a crowded bar.
    var activities: [LiveActivity] {
        guard let lastArrival = queue.lastArrival, let text = NotificationQueue.countText(queue.count) else {
            return []
        }
        let displayTime = appState?.settings.notifications.displayTime
            ?? DesignTokens.Indicator.notificationDefaultDisplayTime
        return [
            LiveActivity(
                id: "count",
                moduleID: moduleID,
                kind: .other,
                symbol: "bell.badge",
                title: String(localized: "\(queue.count) new notifications"),
                priority: DesignTokens.Indicator.notificationCountPriority,
                startedAt: lastArrival,
                finishedAt: lastArrival,
                tint: .accent,
                compactValue: text,
                holdSeconds: TimeInterval(NotificationQueue.displayTime(displayTime))
            ),
        ]
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
        queue = NotificationQueue()
    }
}
