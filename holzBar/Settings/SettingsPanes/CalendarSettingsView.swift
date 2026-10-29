//
//  CalendarSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Calendar module's settings, shown under its row in the Modules pane while the module is
/// on: whether all-day events show, and one switch per calendar.
///
/// The calendars' names are read only while this view is on screen and are held in view state;
/// they are never stored or logged.
struct CalendarSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var calendars = [CalendarInfo]()

    var body: some View {
        @Bindable var settings = appState.settings.calendar
        let permission = appState.permissions.calendar
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Show all-day events", isOn: $settings.showsAllDay)
            if permission.hasPermission {
                Text("Calendars")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                ForEach(calendars) { calendar in
                    Toggle(isOn: shows(calendar.id)) {
                        HStack(spacing: HolzBarTheme.Spacing.sm) {
                            CalendarColorDot(color: calendar.color)
                            Text(verbatim: calendar.title)
                        }
                    }
                }
            } else {
                missingAccess(permission)
            }
        }
        .task(id: permission.hasPermission) {
            calendars = permission.hasPermission ? await CalendarFetcher().calendars() : []
        }
        .onDisappear {
            calendars = []
        }
    }

    /// Whether a calendar shows; switching it flips its identifier in the stored list.
    private func shows(_ calendarID: String) -> Binding<Bool> {
        let settings = appState.settings.calendar
        return Binding {
            CalendarSelection.isVisible(calendarID, hidden: settings.hiddenCalendars)
        } set: { isShown in
            if isShown != CalendarSelection.isVisible(calendarID, hidden: settings.hiddenCalendars) {
                settings.hiddenCalendars = CalendarSelection.toggled(calendarID, in: settings.hiddenCalendars)
            }
        }
    }

    /// The sentence and the button of a missing permission; nothing asks by itself.
    private func missingAccess(_ permission: CalendarPermission) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Text("Calendar access is off")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
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
