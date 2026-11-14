//
//  CalendarReadFreshness.swift
//  holzBar
//

import Foundation

/// Whether the Calendar module's rows from an earlier read may still decide what the hub opens on.
///
/// The module reads its events only while the hub is open, so at the next opening the rows are
/// from the opening before. They may decide at once, without waiting for the new read, only while
/// nothing says they are out of date: the event store has not reported a change since the read
/// (an event deleted, moved or declined posts one), the settings that choose the rows are the
/// same, and the read is not older than ``maximumAge``. The context then still checks each
/// meeting against the clock (a running one, or one that starts within the lead), so a meeting
/// that has ended or is far away never decides. When anything is uncertain the rows do not
/// decide, and the late decision (D-03) brings a real meeting to the front within the first
/// second once the opening's own read has finished.
///
/// The store's change notification is the only thing that learns of a change while the hub is
/// closed; it reads nothing. A read that started before a change and ends after it does not make
/// the rows trusted again (``didRead(startedAt:token:)``): the token taken at its start no longer
/// matches.
nonisolated struct CalendarReadFreshness: Equatable, Sendable {
    /// How old a read may be and still decide at an opening: it also covers a change that no
    /// notification reported, for instance across sleep.
    static let maximumAge: TimeInterval = 30 * 60

    /// When the last read that is still believed started, or `nil` when none is.
    private(set) var readAt: Date?

    /// Counts the events that made an earlier read untrustworthy.
    private var changes = 0

    /// A token to take when a read starts and to give back when it ends.
    var token: Int {
        changes
    }

    /// The event store reported a change, or the settings that choose the rows changed: what was
    /// read before cannot be trusted.
    mutating func didChange() {
        changes += 1
        readAt = nil
    }

    /// A read that started at `startedAt` with `token` has ended. It is believed only when nothing
    /// changed since it started.
    mutating func didRead(startedAt: Date, token: Int) {
        guard token == changes else {
            return
        }
        readAt = startedAt
    }

    /// Nothing is held any more (the module was shut down, or events can no longer be read).
    mutating func reset() {
        didChange()
    }

    /// Whether the rows of the last read may decide now: a read is believed, it is not from the
    /// future (the clock was set back) and it is not older than ``maximumAge``.
    func mayDecide(now: Date) -> Bool {
        guard let readAt else {
            return false
        }
        let age = now.timeIntervalSince(readAt)
        return age >= 0 && age <= Self.maximumAge
    }
}
