import Foundation
import Testing
@testable import HolzBarCore

@Suite("CalendarEvent")
struct CalendarEventTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(attendeeCount: Int? = nil) -> CalendarEvent {
        CalendarEvent(id: "a", title: "Review", start: start, end: start.addingTimeInterval(3600), attendeeCount: attendeeCount)
    }

    @Test("An event without an attendee count stores nil")
    func unknownCount() {
        #expect(event().attendeeCount == nil)
    }

    @Test("A count above zero is kept")
    func keepsCount() {
        #expect(event(attendeeCount: 4).attendeeCount == 4)
    }

    @Test("Zero stays zero, so a row can tell no invitees from an unknown count")
    func zeroStaysZero() {
        #expect(event(attendeeCount: 0).attendeeCount == 0)
    }

    @Test("A negative count is stored as nil")
    func negativeCount() {
        #expect(event(attendeeCount: -1).attendeeCount == nil)
        #expect(event(attendeeCount: Int.min).attendeeCount == nil)
    }

    @Test("The text caps are unchanged and the detail notes are shorter than the stored notes")
    func caps() {
        #expect(CalendarEvent.maximumLocationLength == 500)
        #expect(CalendarEvent.maximumNotesLength == 4_000)
        #expect(CalendarEvent.detailNotesLength == 300)
        #expect(CalendarEvent.detailNotesLength < CalendarEvent.maximumNotesLength)
        let long = CalendarEvent(
            id: "b", title: "T", start: start, end: start,
            location: String(repeating: "l", count: 600), notes: String(repeating: "n", count: 5_000)
        )
        #expect(long.location?.count == 500)
        #expect(long.notes?.count == 4_000)
    }
}
