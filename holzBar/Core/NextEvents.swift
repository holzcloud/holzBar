//
//  NextEvents.swift
//  holzBar
//

import Foundation

/// Which events the Calendar module shows, in what order, and when the list next changes.
///
/// Pure: it reads no clock and no calendar store. The caller passes the moment and the
/// `Calendar` (the user's time zone), so the rules can be tested around midnight and across a
/// time zone change.
nonisolated enum NextEvents {
    /// The most rows the Calendar tab shows.
    static let defaultLimit = 6

    /// Where a row stands relative to now.
    nonisolated enum Phase: Equatable, Sendable {
        /// An event with a time that is on now.
        case happening
        /// An event with a time that starts later.
        case upcoming
        /// An all-day event of today.
        case allDay
    }

    /// One row of the list.
    nonisolated struct Row: Equatable, Sendable, Identifiable {
        let event: CalendarEvent
        let phase: Phase

        var id: String { event.id }
    }

    /// The rows and the next moment the list changes by itself.
    nonisolated struct Selection: Equatable, Sendable {
        let rows: [Row]
        /// The earliest moment after `now` at which an event starts or ends, a join window
        /// opens, or the day changes. Never `nil` and never `now` or earlier.
        let nextBoundary: Date
    }

    /// The end of the window: the start of the day after tomorrow, in `calendar`.
    static func windowEnd(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 2, to: today) ?? now.addingTimeInterval(2 * 86_400)
    }

    /// Chooses the rows to show.
    ///
    /// - Parameters:
    ///   - events: Every event the store returned for the window.
    ///   - now: The moment of the choice.
    ///   - calendar: The user's calendar and time zone; it decides where today and tomorrow end.
    ///   - limit: The most rows to return.
    ///   - includesAllDay: Whether all-day events are shown.
    static func select(
        events: [CalendarEvent],
        now: Date,
        calendar: Calendar,
        limit: Int = defaultLimit,
        includesAllDay: Bool = true
    ) -> Selection {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        let end = windowEnd(now: now, calendar: calendar)

        var allDay = [Row]()
        var timed = [Row]()
        for event in events where !event.isCancelled && !event.isDeclined {
            if event.isAllDay {
                // An end exactly at midnight belongs to the next day; 23:59:59 to this one.
                if includesAllDay, event.start < tomorrow, event.end > today {
                    allDay.append(Row(event: event, phase: .allDay))
                }
            } else if event.end > now, event.start < end {
                timed.append(Row(event: event, phase: event.start <= now ? .happening : .upcoming))
            }
        }

        let ordered = sorted(allDay, by: { $0.event.title }, thenBy: { _ in 0 })
            + sorted(timed.filter { $0.phase == .happening }, by: { $0.event.title }, thenBy: { $0.event.start.timeIntervalSinceReferenceDate })
            + sorted(timed.filter { $0.phase == .upcoming }, by: { $0.event.title }, thenBy: { $0.event.start.timeIntervalSinceReferenceDate })
        let rows = Array(ordered.prefix(max(0, limit)))
        return Selection(rows: rows, nextBoundary: boundary(of: rows, now: now, nextDay: tomorrow))
    }

    /// Sorts by the number first, then by the title, keeping the given order for equal ones.
    private static func sorted(
        _ rows: [Row],
        by title: (Row) -> String,
        thenBy number: (Row) -> Double
    ) -> [Row] {
        rows.enumerated().sorted { left, right in
            let leftNumber = number(left.element)
            let rightNumber = number(right.element)
            if leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            switch title(left.element).compare(title(right.element), options: [.caseInsensitive, .numeric]) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return left.offset < right.offset
            }
        }.map(\.element)
    }

    /// The earliest moment after `now` at which the list or a join state changes.
    private static func boundary(of rows: [Row], now: Date, nextDay: Date) -> Date {
        var earliest = nextDay > now ? nextDay : now.addingTimeInterval(60)
        for row in rows {
            switch row.phase {
            case .allDay:
                break
            case .happening:
                earliest = min(earliest, row.event.end)
            case .upcoming:
                earliest = min(earliest, row.event.start)
                let opens = row.event.start.addingTimeInterval(-MeetingLinks.joinLeadSeconds)
                if opens > now {
                    earliest = min(earliest, opens)
                }
            }
        }
        return earliest > now ? earliest : now.addingTimeInterval(60)
    }
}
