//
//  NotificationsSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Notifications module's settings, shown under its row in the Modules pane while the module
/// is on: a sentence that says what the module reads and that nothing is stored, and the list of
/// apps whose notifications are never shown, each with a button that takes it off the list.
struct NotificationsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let settings = appState.settings.notifications
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            caption(Text("Reads the banners macOS shows, through Accessibility. Nothing is stored."))
            Text("Excluded apps")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.text)
            if settings.excludedApps.isEmpty {
                caption(Text("Hide an app with the crossed-out eye on one of its notifications."))
            } else {
                ForEach(settings.excludedApps, id: \.self) { name in
                    HStack {
                        Text(verbatim: name)
                            .font(HolzBarTheme.Typography.body)
                            .foregroundStyle(HolzBarTheme.Palette.text)
                        Spacer(minLength: 0)
                        Button {
                            settings.include(name)
                        } label: {
                            Image(systemName: "xmark")
                                .font(HolzBarTheme.Typography.caption)
                                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                                .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove"))
                        .help(Text("Remove"))
                    }
                }
            }
        }
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
