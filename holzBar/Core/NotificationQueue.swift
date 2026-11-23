//
//  NotificationQueue.swift
//  holzBar
//

import Foundation

/// The notifications that have arrived and not been seen yet, and when the closed notch's count
/// of them ends.
///
/// It holds identifiers and instants only, never a title, an app name or a text: the privacy rules
/// and the text itself stay in ``NotificationLog`` (D-17). It is a value owned by the Notifications
/// module's runtime and lives in memory only. A notification is unseen from its arrival until the
/// hub has shown the Notifications tab and the tab goes away (``markAllSeen()``), or until it is
/// removed (``forget(_:)``).
nonisolated struct NotificationQueue: Equatable, Sendable {
    /// The most unseen notifications the queue keeps: as many as the log holds.
    static let maximumUnseen = NotificationLog.maximumRecords

    /// The largest count the closed notch spells out; a higher one reads "9+".
    static let largestSpelledCount = 9

    /// The identifiers of the unseen notifications, the newest first, at most ``maximumUnseen``.
    private(set) var unseen = [UUID]()

    /// When the newest notification arrived, or `nil` before the first one. It survives
    /// ``markAllSeen()``.
    private(set) var lastArrival: Date?

    init() {}

    /// How many notifications are unseen.
    var count: Int {
        unseen.count
    }

    /// Notes a new notification. The same identifier again changes nothing, so a notification
    /// counts once and does not restart the count; the oldest unseen one leaves beyond
    /// ``maximumUnseen``.
    mutating func arrived(_ id: UUID, at date: Date) {
        guard !unseen.contains(id) else {
            return
        }
        unseen.insert(id, at: 0)
        if unseen.count > Self.maximumUnseen {
            unseen.removeLast(unseen.count - Self.maximumUnseen)
        }
        lastArrival = date
    }

    /// Marks every notification as seen. ``lastArrival`` stays.
    mutating func markAllSeen() {
        unseen.removeAll()
    }

    /// Forgets one notification, such as a removed one; an unknown identifier changes nothing.
    mutating func forget(_ id: UUID) {
        unseen.removeAll { $0 == id }
    }

    /// Whether the notification is unseen.
    func isUnseen(_ id: UUID) -> Bool {
        unseen.contains(id)
    }

    /// The text the closed notch shows beside the bell: nothing for none, "1" to "9", else "9+".
    static func countText(_ count: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        return count > largestSpelledCount ? "\(largestSpelledCount)+" : String(count)
    }

    /// The nearest of the display times the user may choose, in seconds; a tie goes to the shorter
    /// one. A value outside the choices, such as a stored one a user edited by hand, lands on the
    /// first or the last.
    static func displayTime(_ stored: Int) -> Int {
        var best = DesignTokens.Indicator.notificationDefaultDisplayTime
        var bestDistance = Int.max
        for choice in DesignTokens.Indicator.notificationDisplayTimes.sorted() {
            let distance = abs(choice - stored)
            if distance < bestDistance {
                best = choice
                bestDistance = distance
            }
        }
        return best
    }

    /// The moment the count ends: the last arrival plus the display time, in whole seconds, or
    /// `nil` before any arrival. At that instant the count is gone; one second earlier it shows.
    func countEnds(displayTime stored: Int) -> Date? {
        lastArrival?.addingTimeInterval(TimeInterval(Self.displayTime(stored)))
    }
}
