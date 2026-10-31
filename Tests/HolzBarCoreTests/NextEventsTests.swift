import Foundation
import Testing
@testable import HolzBarCore

@Suite("NextEvents")
struct NextEventsTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .gmt
    private let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    private func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// A moment in the given zone.
    private func moment(_ zone: TimeZone, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar(zone).date(from: components) ?? .distantPast
    }

    private func event(
        _ id: String,
        _ title: String? = nil,
        from start: Date,
        to end: Date,
        allDay: Bool = false,
        cancelled: Bool = false,
        declined: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, title: title ?? id, start: start, end: end, isAllDay: allDay,
            isCancelled: cancelled, isDeclined: declined
        )
    }

    // 2026-10-29, 10:00 in Zurich.
    private var now: Date { moment(zurich, 10, 29, 10, 0) }

    private func ids(_ selection: NextEvents.Selection) -> [String] {
        selection.rows.map(\.event.id)
    }

    @Test("A running event is happening, later ones are upcoming sorted by start, an ended one is left out")
    func happeningThenUpcoming() {
        let events = [
            event("later", from: moment(zurich, 10, 29, 15, 0), to: moment(zurich, 10, 29, 16, 0)),
            event("running", from: moment(zurich, 10, 29, 9, 30), to: moment(zurich, 10, 29, 10, 30)),
            event("soon", from: moment(zurich, 10, 29, 11, 0), to: moment(zurich, 10, 29, 12, 0)),
            event("over", from: moment(zurich, 10, 29, 8, 0), to: moment(zurich, 10, 29, 9, 0)),
            event("endsNow", from: moment(zurich, 10, 29, 9, 0), to: now),
        ]
        let selection = NextEvents.select(events: events, now: now, calendar: calendar(zurich))
        #expect(ids(selection) == ["running", "soon", "later"])
        #expect(selection.rows.map(\.phase) == [.happening, .upcoming, .upcoming])
    }

    @Test("Equal starts sort by title and keep their order when the titles are equal")
    func equalStartsSortByTitle() {
        let start = moment(zurich, 10, 29, 11, 0)
        let end = moment(zurich, 10, 29, 12, 0)
        let events = [
            event("1", "Standup", from: start, to: end),
            event("2", "Budget", from: start, to: end),
            event("3", "standup", from: start, to: end),
            event("4", "Alpha", from: start, to: end),
        ]
        let selection = NextEvents.select(events: events, now: now, calendar: calendar(zurich))
        #expect(ids(selection) == ["4", "2", "1", "3"])
    }

    @Test("The window ends with tomorrow: the day after tomorrow is left out, an event spanning midnight is shown")
    func windowEndsWithTomorrow() {
        let events = [
            event("tomorrow", from: moment(zurich, 10, 30, 23, 0), to: moment(zurich, 10, 31, 0, 30)),
            event("dayAfter", from: moment(zurich, 10, 31, 9, 0), to: moment(zurich, 10, 31, 10, 0)),
            event("overnight", from: moment(zurich, 10, 29, 9, 0), to: moment(zurich, 10, 30, 2, 0)),
        ]
        let selection = NextEvents.select(events: events, now: now, calendar: calendar(zurich))
        #expect(ids(selection) == ["overnight", "tomorrow"])
        #expect(NextEvents.windowEnd(now: now, calendar: calendar(zurich)) == moment(zurich, 10, 31, 0, 0))
    }

    @Test("Cancelled and declined events are left out, and empty input gives no rows")
    func cancelledAndDeclined() {
        let start = moment(zurich, 10, 29, 11, 0)
        let end = moment(zurich, 10, 29, 12, 0)
        let events = [
            event("cancelled", from: start, to: end, cancelled: true),
            event("declined", from: start, to: end, declined: true),
            event("fine", from: start, to: end),
        ]
        #expect(ids(NextEvents.select(events: events, now: now, calendar: calendar(zurich))) == ["fine"])
        let empty = NextEvents.select(events: [], now: now, calendar: calendar(zurich))
        #expect(empty.rows.isEmpty)
        #expect(empty.nextBoundary > now)
    }

    @Test("The limit keeps the first rows of the order, happening first")
    func limitKeepsTheFirstRows() {
        var events = [event("running", from: moment(zurich, 10, 29, 9, 0), to: moment(zurich, 10, 29, 11, 0))]
        for hour in 12...17 {
            events.append(event("e\(hour)", from: moment(zurich, 10, 29, hour, 0), to: moment(zurich, 10, 29, hour, 30)))
        }
        let limited = NextEvents.select(events: events, now: now, calendar: calendar(zurich), limit: 3)
        #expect(ids(limited) == ["running", "e12", "e13"])
        #expect(NextEvents.select(events: events, now: now, calendar: calendar(zurich)).rows.count == NextEvents.defaultLimit)
        #expect(NextEvents.select(events: events, now: now, calendar: calendar(zurich), limit: 0).rows.isEmpty)
    }

    @Test("The end of tomorrow is the calendar's own midnight in another time zone")
    func otherTimeZone() {
        // 2026-10-29 10:00 in Zurich is 18:00 on the same day in Tokyo; a Tokyo event at
        // 2026-10-31 00:30 is two days ahead there but 17:30 on the 30th in Zurich.
        let tokyoEvent = event("t", from: moment(tokyo, 10, 31, 0, 30), to: moment(tokyo, 10, 31, 1, 0))
        let inTokyo = NextEvents.select(events: [tokyoEvent], now: now, calendar: calendar(tokyo))
        let inZurich = NextEvents.select(events: [tokyoEvent], now: now, calendar: calendar(zurich))
        #expect(inTokyo.rows.isEmpty)
        #expect(ids(inZurich) == ["t"])
        #expect(NextEvents.windowEnd(now: now, calendar: calendar(tokyo)) == moment(tokyo, 10, 31, 0, 0))
    }

    @Test("Text is cut when an event is made, and the end is never before the start")
    func capsAndOrder() {
        let long = String(repeating: "a", count: 5_000)
        let made = CalendarEvent(
            id: "x", title: long, start: now, end: now.addingTimeInterval(-60),
            location: long, notes: long
        )
        #expect(made.title.count == CalendarEvent.maximumTitleLength)
        #expect(made.location?.count == CalendarEvent.maximumLocationLength)
        #expect(made.notes?.count == CalendarEvent.maximumNotesLength)
        #expect(made.end == made.start)
        #expect(CalendarColor(red: 2, green: -1, blue: .nan).red == 1)
        #expect(CalendarColor(red: 2, green: -1, blue: .nan).green == 0)
        #expect(CalendarColor(red: 2, green: -1, blue: .nan).blue == 0.6)
    }

    // MARK: All-day

    @Test("An all-day event of today comes first; ones that ended yesterday or start later are left out")
    func allDayRule() {
        let events = [
            event("timed", from: moment(zurich, 10, 29, 11, 0), to: moment(zurich, 10, 29, 12, 0)),
            event("holiday", "Holiday", from: moment(zurich, 10, 29, 0, 0), to: moment(zurich, 10, 29, 23, 59, 59), allDay: true),
            event("yesterday", from: moment(zurich, 10, 28, 0, 0), to: moment(zurich, 10, 28, 23, 59, 59), allDay: true),
            event("tomorrow", from: moment(zurich, 10, 30, 0, 0), to: moment(zurich, 10, 30, 23, 59, 59), allDay: true),
            event("trip", "Anniversary", from: moment(zurich, 10, 27, 0, 0), to: moment(zurich, 10, 30, 23, 59, 59), allDay: true),
        ]
        let selection = NextEvents.select(events: events, now: now, calendar: calendar(zurich))
        #expect(ids(selection) == ["trip", "holiday", "timed"])
        #expect(selection.rows.map(\.phase) == [.allDay, .allDay, .upcoming])
        let without = NextEvents.select(events: events, now: now, calendar: calendar(zurich), includesAllDay: false)
        #expect(ids(without) == ["timed"])
    }

    @Test("An all-day event that ends exactly at midnight does not cover the next day; 23:59:59 does")
    func allDayEndsAtMidnight() {
        let endsAtMidnight = event("a", from: moment(zurich, 10, 28, 0, 0), to: moment(zurich, 10, 29, 0, 0), allDay: true)
        let endsBefore = event("b", from: moment(zurich, 10, 28, 0, 0), to: moment(zurich, 10, 29, 23, 59, 59), allDay: true)
        let selection = NextEvents.select(events: [endsAtMidnight, endsBefore], now: now, calendar: calendar(zurich))
        #expect(ids(selection) == ["b"])
    }

    // MARK: Next boundary

    @Test("The next boundary is the opening of the join window when that is the earliest")
    func boundaryIsTheJoinWindow() {
        let start = now.addingTimeInterval(90 * 60)
        let selection = NextEvents.select(
            events: [event("e", from: start, to: start.addingTimeInterval(3_600))], now: now, calendar: calendar(zurich)
        )
        #expect(selection.nextBoundary == start.addingTimeInterval(-600))
    }

    @Test("The next boundary is the earliest of a start, the end of a running event and midnight")
    func boundaryIsTheEarliest() {
        let running = event("r", from: moment(zurich, 10, 29, 9, 0), to: moment(zurich, 10, 29, 10, 20))
        let later = event("l", from: moment(zurich, 10, 29, 10, 15), to: moment(zurich, 10, 29, 11, 0))
        // The join window of "l" opens at 10:05, before the end of "r" at 10:20.
        let first = NextEvents.select(events: [running, later], now: now, calendar: calendar(zurich))
        #expect(first.nextBoundary == moment(zurich, 10, 29, 10, 5))
        // Once the window is open, the end of the running event is the next change.
        let second = NextEvents.select(events: [running, later], now: moment(zurich, 10, 29, 10, 6), calendar: calendar(zurich))
        #expect(second.nextBoundary == moment(zurich, 10, 29, 10, 15))
    }

    @Test("With no events the next boundary is the next midnight, and it is always after now")
    func boundaryIsMidnightWithNoEvents() {
        let selection = NextEvents.select(events: [], now: now, calendar: calendar(zurich))
        #expect(selection.nextBoundary == moment(zurich, 10, 30, 0, 0))
        let lateNow = moment(zurich, 10, 29, 23, 59, 59)
        let late = NextEvents.select(events: [], now: lateNow, calendar: calendar(zurich))
        #expect(late.nextBoundary == moment(zurich, 10, 30, 0, 0))
        #expect(late.nextBoundary > lateNow)
    }

    @Test("The next boundary follows the calendar's own midnight across time zones")
    func boundaryFollowsTheTimeZone() {
        let inTokyo = NextEvents.select(events: [], now: now, calendar: calendar(tokyo))
        #expect(inTokyo.nextBoundary == moment(tokyo, 10, 30, 0, 0))
        #expect(inTokyo.nextBoundary < NextEvents.select(events: [], now: now, calendar: calendar(zurich)).nextBoundary)
    }

    @Test("The boundary is also right across the end of daylight saving time")
    func boundaryAcrossDaylightSavingEnd() {
        // 2026-10-25 is the day the clocks go back in Zurich: the day has 25 hours.
        let sunday = moment(zurich, 10, 25, 1, 0)
        let selection = NextEvents.select(events: [], now: sunday, calendar: calendar(zurich))
        #expect(selection.nextBoundary == moment(zurich, 10, 26, 0, 0))
        // 23 hours on the clock, 24 hours elapsed.
        #expect(selection.nextBoundary.timeIntervalSince(sunday) == 24 * 3_600)
    }
}
