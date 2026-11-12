//
//  ImportProfileSheet.swift
//  holzBar
//

import AppKit
import SwiftUI

/// Shows what is in a shared profile before it is imported. Importing adds the profile to
/// the list; it moves no item, and nothing runs.
struct ImportProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shared: SharedProfile
    let profiles: LayoutProfiles

    private var finalName: String {
        SharedProfile.uniqueName(shared.name, among: profiles.profiles.map(\.name))
    }

    private var installedCount: Int {
        shared.apps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Import Profile")
                .font(HolzBarTheme.Typography.title)
                .accessibilityAddTraits(.isHeader)
            Text("The profile \u{201C}\(finalName)\u{201D} has \(shared.apps.count) apps, \(installedCount) of them installed on this Mac. Importing adds it to your profiles; it moves nothing until you apply it.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                SettingsGroup {
                    ForEach(shared.apps, id: \.id) { entry in
                        SettingsValueRow(
                            Text(verbatim: AutomationDescription.applicationName(for: entry.id)),
                            value: Text(verbatim: entry.id)
                        )
                    }
                }
            }
            .frame(height: 220)
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") {
                    profiles.importShared(shared)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 480)
    }
}
