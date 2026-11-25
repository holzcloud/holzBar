//
//  AlertNotificationPlan.swift
//  holzBar
//

import Foundation

/// Whether macOS lets holzBar post notifications, as far as holzBar knows.
nonisolated enum NotificationAccess: Equatable, Sendable {
    /// macOS has not been asked yet.
    case notDetermined
    /// The user refused, or the request failed: holzBar does not ask again.
    case denied
    /// Notifications may be posted.
    case allowed

    /// What the answer to the one permission request means. A request that failed (`nil`) counts as
    /// refused, so the notch alert never waits on the notification channel.
    static func afterRequest(granted: Bool?) -> NotificationAccess {
        granted == true ? .allowed : .denied
    }
}

/// One thing the host does for an alert effect, on one of its two channels.
nonisolated enum AlertChannelAction: Equatable, Sendable {
    /// The alert's live activity appears or changes in the notch.
    case showInNotch(AlertSignal)
    /// The alert's live activity becomes its done state in the notch.
    case finishInNotch(AlertSignal)
    /// The alert's live activity goes at once, with no done state.
    case removeFromNotch(AlertSignal)
    /// The alert is posted as a system notification.
    case deliver(AlertSignal)
    /// The alert's system notification is removed.
    case withdraw(AlertSignal)
}

/// Which channels an alert reaches (ALRT-03, D-01, D-05, D-21, D-22).
///
/// The evaluator's ``ThresholdEvaluator/Effect`` is the one source. The notch is the primary
/// channel and never depends on anything else: every effect yields exactly one notch action
/// whatever the notification switch and the permission say (D-01). The system notification is the
/// optional second channel, derived from the same effect, and exists only with the switch on and
/// the permission given.
nonisolated enum AlertNotificationPlan {
    /// The prefix of every notification identifier holzBar posts for an alert.
    static let identifierPrefix = "com.holzcloud.holzBar.alert."

    /// The fixed identifier of a rule's notification, so a new delivery replaces the rule's
    /// previous one instead of stacking (D-05).
    static func identifier(for signal: AlertSignal) -> String {
        identifierPrefix + signal.rawValue
    }

    /// The identifier of the Test alert's notification (D-16).
    static let testIdentifier = identifierPrefix + "test"

    /// Every identifier holzBar can have posted: one per rule and the test alert's.
    static var allIdentifiers: [String] {
        AlertSignal.allCases.map { identifier(for: $0) } + [testIdentifier]
    }

    /// The thread of a rule's notifications: one per rule (D-22).
    static func threadIdentifier(for signal: AlertSignal) -> String {
        identifier(for: signal)
    }

    /// The actions for one evaluator effect.
    ///
    /// A fire is delivered; an update is not, because every delivery with the same identifier
    /// alerts the user again, so a value or severity change updates the notch only (one
    /// notification per rule per episode). A clear or an end removes the notification again.
    static func actions(
        for effect: ThresholdEvaluator.Effect,
        notificationsOn: Bool,
        access: NotificationAccess
    ) -> [AlertChannelAction] {
        let canNotify = notificationsOn && access == .allowed
        switch effect {
        case .fired(let snapshot):
            return canNotify
                ? [.showInNotch(snapshot.signal), .deliver(snapshot.signal)]
                : [.showInNotch(snapshot.signal)]
        case .updated(let snapshot):
            return [.showInNotch(snapshot.signal)]
        case .cleared(let signal):
            // A withdrawal is harmless without a delivery, so it follows the switch alone: the
            // notification of an episode that began while allowed is still removed.
            return notificationsOn ? [.finishInNotch(signal), .withdraw(signal)] : [.finishInNotch(signal)]
        case .ended(let signal):
            return notificationsOn ? [.removeFromNotch(signal), .withdraw(signal)] : [.removeFromNotch(signal)]
        }
    }
}
