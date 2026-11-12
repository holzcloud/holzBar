//
//  CalendarSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Calendar module's settings, in the open area of the module's row: whether all-day events
/// show, and which calendars, chosen in a sheet. Without access, one state line says so with one
/// button; nothing asks by itself.
///
/// The calendars' names are read only while this view is on screen and are held in view state;
/// they are never stored or logged.
struct CalendarSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var calendars = [CalendarInfo]()
    @State private var isChoosingCalendars = false

    var body: some View {
        @Bindable var settings = appState.settings.calendar
        let permission = appState.permissions.calendar
        // A container only so that the task and the clean-up run once.
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(.modulesCalendarShowsAllDay, isOn: $settings.showsAllDay)
            if permission.hasPermission {
                SettingsButtonRow(.modulesCalendarCalendars, small: calendarCount(settings: settings)) {
                    Button("Choose…") {
                        isChoosingCalendars = true
                    }
                    .disabled(calendars.isEmpty)
                }
                .sheet(isPresented: $isChoosingCalendars) {
                    CalendarChoiceSheet(calendars: calendars, settings: settings)
                }
            } else {
                SettingsStateLine(.warning, Text("Calendar access is off")) {
                    if CalendarAuthorization.current == .notDetermined {
                        Button("Allow Calendar Access") {
                            permission.performRequest()
                        }
                    } else {
                        Button("Open System Settings") {
                            permission.performRequest()
                        }
                    }
                }
            }
        }
        .task(id: permission.hasPermission) {
            calendars = permission.hasPermission ? await CalendarFetcher().calendars() : []
        }
        .onDisappear {
            calendars = []
        }
    }

    /// How many of the calendars show, as "<shown> of <total>"; nothing while none was read.
    private func calendarCount(settings: CalendarSettings) -> Text? {
        guard !calendars.isEmpty else {
            return nil
        }
        let shown = calendars.filter { CalendarSelection.isVisible($0.id, hidden: settings.hiddenCalendars) }.count
        return Text("\(shown) of \(calendars.count)")
    }
}

/// The calendars to show, one switch each with the calendar's colour. The names are user data,
/// shown as they are and never stored or logged.
private struct CalendarChoiceSheet: View {
    let calendars: [CalendarInfo]
    let settings: CalendarSettings

    var body: some View {
        SettingsListSheet(Text("Calendars")) {
            SettingsGroup {
                ForEach(calendars) { calendar in
                    SettingsRow(Text(verbatim: calendar.title)) {
                        HStack(spacing: HolzBarTheme.Spacing.sm) {
                            CalendarColorDot(color: calendar.color)
                            SettingsSwitch(isOn: shows(calendar.id), label: Text(verbatim: calendar.title))
                        }
                    }
                }
            }
        }
    }

    /// Whether a calendar shows; switching it flips its identifier in the stored list.
    private func shows(_ calendarID: String) -> Binding<Bool> {
        Binding {
            CalendarSelection.isVisible(calendarID, hidden: settings.hiddenCalendars)
        } set: { isShown in
            if isShown != CalendarSelection.isVisible(calendarID, hidden: settings.hiddenCalendars) {
                settings.hiddenCalendars = CalendarSelection.toggled(calendarID, in: settings.hiddenCalendars)
            }
        }
    }
}
