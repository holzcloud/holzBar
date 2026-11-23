//
//  CalendarSettings.swift
//  holzBar
//

import Observation

/// Model for the Calendar module's settings: whether all-day events show, which calendars are
/// switched off and how long before a meeting the closed notch counts down. Each saves itself in
/// its `didSet`. The list of switched-off calendars names the user's accounts, so it stays on this
/// Mac (never exported, imported or synced); the countdown lead is a plain number and travels
/// with a settings file.
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

    /// How long before a meeting the closed notch counts down to it: one of ``CountdownLead``, five
    /// minutes by default. The picker offers only those; what is stored is snapped to the nearest.
    var countdownLead = CountdownLead.defaultLead {
        didSet {
            guard countdownLead != oldValue else {
                return
            }
            Defaults.set(countdownLead.rawValue, forKey: .calendarCountdownLead)
        }
    }

    /// Loads the stored settings. The stored list can hold anything, so it is read safely.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .calendarShowsAllDay, assign: &showsAllDay)
        if let stored = Defaults.stringArray(forKey: .calendarHiddenCalendars) {
            hiddenCalendars = CalendarSelection.cleaned(stored)
        }
        Defaults.ifPresent(key: .calendarCountdownLead) { (stored: Double) in
            let clamped = Defaults.Key.calendarCountdownLead.clamped(
                stored,
                fallback: Double(CountdownLead.defaultLead.rawValue)
            )
            countdownLead = CountdownLead.snapped(Int(clamped.rounded(.down)))
        }
    }
}
