//
//  NotificationsSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Notifications module's settings, in the open area of the module's row: a note line that
/// says what the module reads and that nothing is stored, the apps whose notifications are never
/// shown (edited in a sheet), and a state line while holzBar lacks Accessibility.
///
/// The state line's button only opens System Settings; it never asks for the permission, which
/// would show the system prompt.
struct NotificationsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isEditingExclusions = false

    var body: some View {
        let settings = appState.settings.notifications
        SettingsNoteLine(Text("Reads the banners macOS shows, through Accessibility. Nothing is stored."))
        SettingsButtonRow(
            .modulesNotificationsExcludedApps,
            small: settings.excludedApps.isEmpty
                ? Text("none yet")
                : Text(settings.excludedApps.count, format: .number)
        ) {
            Button("Edit…") {
                isEditingExclusions = true
            }
            .disabled(settings.excludedApps.isEmpty)
        }
        .sheet(isPresented: $isEditingExclusions) {
            ExcludedAppsSheet(settings: settings)
        }
        if !appState.permissions.accessibility.hasPermission {
            SettingsStateLine(.warning, Text("Accessibility access is off")) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

/// The apps whose notifications are never shown; removing one acts at once. App names are shown
/// as they are, never looked up as string keys.
private struct ExcludedAppsSheet: View {
    let settings: NotificationsSettings

    var body: some View {
        SettingsListSheet(Text("Excluded apps")) {
            if settings.excludedApps.isEmpty {
                SettingsStateLine(.info, Text("No excluded apps"))
            } else {
                SettingsGroup {
                    ForEach(settings.excludedApps, id: \.self) { name in
                        SettingsButtonRow(Text(verbatim: name)) {
                            Button("Remove") {
                                settings.include(name)
                            }
                            .accessibilityLabel(Text("Remove \(name)"))
                        }
                    }
                }
            }
        }
    }
}
