//
//  CalendarEvent.swift
//  holzBar
//

import Foundation

/// A calendar's colour as red, green and blue from 0 to 1 in sRGB, so that the pure logic
/// carries no AppKit colour.
nonisolated struct CalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// A grey for a calendar whose colour is unknown.
    static let unknown = CalendarColor(red: 0.6, green: 0.6, blue: 0.6)

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.6
    }
}

/// One event of the calendar, as plain values: what the Calendar module of the Notch hub shows.
///
/// The text is cut when the value is made, so a huge event cannot make a huge row. The value
/// lives in memory for the shown window only; it is never written to a file or a log.
nonisolated struct CalendarEvent: Equatable, Sendable, Identifiable {
    /// The longest title kept, in characters.
    static let maximumTitleLength = 300
    /// The longest location kept, in characters.
    static let maximumLocationLength = 500
    /// The longest notes kept, in characters.
    static let maximumNotesLength = 4_000

    /// Unique for one occurrence: a recurring event has one id per instance.
    let id: String
    let title: String
    let start: Date
    /// Never before the start.
    let end: Date
    let isAllDay: Bool
    /// The identifier of the calendar the event is in.
    let calendarID: String
    let calendarColor: CalendarColor
    let location: String?
    let notes: String?
    let url: URL?
    let isCancelled: Bool
    let isDeclined: Bool

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        calendarColor: CalendarColor = .unknown,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        isCancelled: Bool = false,
        isDeclined: Bool = false
    ) {
        self.id = id
        self.title = String(title.prefix(Self.maximumTitleLength))
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarColor = calendarColor
        self.location = location.map { String($0.prefix(Self.maximumLocationLength)) }
        self.notes = notes.map { String($0.prefix(Self.maximumNotesLength)) }
        self.url = url
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
    }
}

/// A calendar macOS lists, for the list of calendars in the module's settings. The name is read
/// only while that list is open and is never stored or logged.
nonisolated struct CalendarInfo: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let color: CalendarColor
}
