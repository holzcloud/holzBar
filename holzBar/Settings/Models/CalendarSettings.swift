//
//  CalendarSettings.swift
//  holzBar
//

import Observation

/// Model for the Calendar module's settings: whether all-day events show and which calendars
/// are switched off. Each saves itself in its `didSet`. The list of switched-off calendars
/// names the user's accounts, so it stays on this Mac (never exported, imported or synced).
@MainActor
@Observable
final class CalendarSettings {
    /// Whether all-day events show in the Calendar tab. On by default.
    var showsAllDay = true {
        didSet {
            Defaults.set(showsAllDay, forKey: .calendarShowsAllDay)
        }
    }

    /// The identifiers of the calendars the user switched off. Every other calendar shows.
    var hiddenCalendars = Set<String>() {
        didSet {
            Defaults.set(hiddenCalendars.sorted(), forKey: .calendarHiddenCalendars)
        }
    }

    /// Loads the stored settings. The stored list can hold anything, so it is read safely.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .calendarShowsAllDay, assign: &showsAllDay)
        if let stored = Defaults.stringArray(forKey: .calendarHiddenCalendars) {
            hiddenCalendars = CalendarSelection.cleaned(stored)
        }
    }
}
