//
//  CalendarFetcher.swift
//  holzBar
//

import CoreGraphics
import EventKit
import Foundation

/// Owns the event store of the Calendar module and returns plain values.
///
/// `EKEventStore` is not documented as thread-safe, so exactly one store lives inside this
/// actor, created on first use and only once the user has allowed full access, and nothing
/// but `Sendable` copies leaves it. The read runs off the main actor. The values hold event
/// text and live in memory only; nothing here is written to a file or the log.
actor CalendarFetcher {
    private var store: EKEventStore?

    /// The events that overlap `start` to `end`, from every calendar. Empty unless the user has
    /// allowed full access.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard let store = readableStore() else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.event(from:))
    }

    /// Drops the store, so the next read makes a new one. Called after a grant, because a store
    /// made before it may not see the events.
    func reset() {
        store = nil
    }

    private func readableStore() -> EKEventStore? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            store = nil
            return nil
        }
        if let store {
            return store
        }
        let made = EKEventStore()
        store = made
        return made
    }

    // MARK: Conversion

    private static func event(from event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else {
            return nil
        }
        let calendarID = event.calendar?.calendarIdentifier ?? ""
        // Each instance of a recurring event has its own start, so the id is unique per row.
        let id = "\(event.eventIdentifier ?? calendarID)@\(Int(start.timeIntervalSince1970))"
        return CalendarEvent(
            id: id,
            title: event.title ?? "",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarID: calendarID,
            calendarColor: color(of: event.calendar?.cgColor),
            location: event.location,
            notes: event.notes,
            url: event.url,
            isCancelled: event.status == .canceled,
            isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        )
    }

    /// The calendar's colour in sRGB.
    private static func color(of cgColor: CGColor?) -> CalendarColor {
        guard let cgColor,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return .unknown
        }
        return CalendarColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}
