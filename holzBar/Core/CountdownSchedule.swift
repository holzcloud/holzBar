//
//  CountdownSchedule.swift
//  holzBar
//

import Foundation

/// How long before a meeting the closed notch starts to count down, in minutes (Phase 96, D-18).
/// The raw values are stored; new ones are only appended.
nonisolated enum CountdownLead: Int, CaseIterable, Sendable {
    case off = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15

    /// The default: five minutes.
    static let defaultLead = CountdownLead.fiveMinutes

    /// The lead as seconds, or `nil` for off.
    var seconds: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue) * 60
    }

    /// The nearest choice to a stored value; a tie goes to the shorter. A value outside the choices,
    /// such as one a user edited by hand, lands on the first or the last.
    static func snapped(_ stored: Int) -> CountdownLead {
        var best = defaultLead
        var bestDistance = Int.max
        for choice in allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let distance = abs(choice.rawValue - stored)
            if distance < bestDistance {
                best = choice
                bestDistance = distance
            }
        }
        return best
    }
}

/// The meeting countdown of the closed notch as pure decisions (D-18, D-24).
///
/// The Calendar runtime holds only the next meeting's start time while the hub is closed. From it
/// and the lead this turns out a ``Plan`` with at most two one-shot wakes: the start of the
/// countdown (the start minus the lead) and the switch to amber (60 seconds before the start). The
/// end needs no wake of its own: the activity finishes at the meeting's start with no hold, so the
/// hub's board drops it there. Nothing here reads a clock or polls; the caller passes the moment.
nonisolated enum CountdownSchedule {
    /// How long before the start the countdown turns amber, in seconds.
    static let amberLead: TimeInterval = 60

    /// The countdown's priority among live activities: above the notification count (12), below a
    /// flash (40). A constant of the schedule, not a design token.
    static let priority = 15

    /// When to show, when to turn amber and when the meeting starts.
    nonisolated struct Plan: Equatable, Sendable {
        /// The moment the countdown starts to show (may lie in the past).
        let startsAt: Date
        /// The moment it turns amber (may lie in the past).
        let amberAt: Date
        /// The meeting's start, when the countdown ends.
        let meetingStart: Date
    }

    /// The plan for the next start, or `nil` for no start, a lead that is off or a start at or
    /// before `now`.
    static func plan(nextStart: Date?, lead: CountdownLead, now: Date) -> Plan? {
        guard let nextStart, nextStart > now, let seconds = lead.seconds else {
            return nil
        }
        return Plan(
            startsAt: nextStart.addingTimeInterval(-seconds),
            amberAt: nextStart.addingTimeInterval(-amberLead),
            meetingStart: nextStart
        )
    }

    /// The next one-shot wake after `now`: the start of the countdown, then the amber switch, then
    /// `nil` (the end is the board's).
    static func nextWake(_ plan: Plan, now: Date) -> Date? {
        if now < plan.startsAt {
            return plan.startsAt
        }
        if now < plan.amberAt {
            return plan.amberAt
        }
        return nil
    }

    /// The wake that carries the countdown from a meeting to the one after it, once no wake of the
    /// meeting itself is left: the start of the next meeting's countdown (its start minus the lead),
    /// but not before this meeting has started, since the notch counts down to one meeting at a
    /// time. It is the first of that next meeting's two wakes, so no meeting has more than two.
    /// `nil` without a following start, with the lead off, or when the following start is not after
    /// this meeting's.
    static func followingWake(after plan: Plan, followingStart: Date?, lead: CountdownLead, now: Date) -> Date? {
        guard let followingStart, followingStart > plan.meetingStart, let seconds = lead.seconds else {
            return nil
        }
        let wake = max(plan.meetingStart, followingStart.addingTimeInterval(-seconds))
        return wake > now ? wake : nil
    }

    /// Whether the countdown is in its last minute.
    static func isAmber(_ plan: Plan, now: Date) -> Bool {
        now >= plan.amberAt
    }
}
