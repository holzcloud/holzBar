//
//  UserNotificationCenterNotifier.swift
//  holzBar
//

import Foundation
import OSLog
import UserNotifications

/// Answers how a notification of holzBar is presented while holzBar is the active app, so an alert
/// shows as a banner and in the list while holzBar's Settings window is in front. Without this
/// answer macOS shows nothing for the foreground app. The answer is banner and list: the older
/// alert option is deprecated.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// Posts and removes the system notifications of the System alerts module (ALRT-03, D-05, D-22).
///
/// **This file is the only place in holzBar that touches the notification framework.** It sends
/// nothing off the Mac: a notification is a local request to Notification Center. A notification
/// carries a rule's title and value text only, a fixed identifier per rule so a new delivery
/// replaces the rule's previous one, and the rule's thread. It requests no sound, no badge, no
/// attachment and no action, and sets no interruption level, so the default applies and no
/// entitlement is needed.
///
/// macOS is asked for the permission only by ``requestPermission()``, which the caller makes only
/// when the user switches System notifications on. Nothing else in this file asks.
@MainActor
final class UserNotificationCenterNotifier {
    private let delegate = AlertNotificationDelegate()
    private let logger = Logger(category: "AlertNotifications")

    /// Makes the delegate that lets an alert show while holzBar is in front the center's delegate.
    func installDelegate() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// What macOS says now. It never asks: it only reads the authorization status. The status is
    /// mapped inside the call so no framework object crosses an actor.
    func access() async -> NotificationAccess {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        default:
            return .notDetermined
        }
    }

    /// Asks macOS for permission to show alerts, the one ask of ALRT-03. Only the alert option is
    /// requested, never a sound or a badge. A request that throws counts as refused.
    func requestPermission() async -> NotificationAccess {
        let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        return NotificationAccess.afterRequest(granted: granted)
    }

    /// Posts one notification at once, or replaces the one with the same identifier.
    func deliver(identifier: String, title: String, body: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("An alert notification was delivered")
        } catch {
            // The error can name a path or a state, so only that it failed is logged.
            logger.notice("An alert notification could not be delivered")
        }
    }

    /// Removes the notifications with these identifiers from Notification Center, and any still
    /// pending.
    func withdraw(identifiers: [String]) {
        guard !identifiers.isEmpty else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
