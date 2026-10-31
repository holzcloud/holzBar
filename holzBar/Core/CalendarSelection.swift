//
//  CalendarSelection.swift
//  holzBar
//

import Foundation

/// Which calendars the Calendar module shows: all of them except the ones the user switched
/// off. The hidden ones are stored as a list of the calendars' identifiers, on this Mac only.
nonisolated enum CalendarSelection {
    /// The most identifiers kept.
    static let maximumCount = 200

    /// The longest identifier kept, in characters.
    static let maximumLength = 200

    /// Whether the calendar with this identifier is shown. An identifier nobody hid is shown,
    /// and so is a calendar that no longer exists: a list of hidden calendars hides nothing it
    /// does not name.
    static func isVisible(_ calendarID: String, hidden: Set<String>) -> Bool {
        !hidden.contains(calendarID)
    }

    /// The set after the calendar was switched: hidden becomes shown and shown becomes hidden.
    static func toggled(_ calendarID: String, in hidden: Set<String>) -> Set<String> {
        var result = hidden
        if result.remove(calendarID) == nil {
            result.insert(calendarID)
        }
        return result
    }

    /// A stored list read safely: it can hold anything, because another process of the user may
    /// have written it. Duplicates, empty identifiers and over-long ones are dropped, and at
    /// most ``maximumCount`` identifiers are kept (the first ones in sorted order).
    static func cleaned(_ stored: [String]) -> Set<String> {
        let valid = Set(stored.filter { !$0.isEmpty && $0.count <= maximumLength })
        guard valid.count > maximumCount else {
            return valid
        }
        return Set(valid.sorted().prefix(maximumCount))
    }
}
