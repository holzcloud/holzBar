//
//  ShareProfileSheet.swift
//  holzBar
//

import AppKit
import SwiftUI

/// Chooses which applications go into a shared profile, then saves the file. The file holds
/// the applications listed here and their sections; nothing else of this Mac.
struct ShareProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: LayoutProfile
    @State private var entries: [SharedProfile.Entry] = []
    @State private var excluded = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Share Profile")
                .font(HolzBarTheme.Typography.title)
                .accessibilityAddTraits(.isHeader)
            Text("The file lists these apps and the section of each. It holds no display, Wi-Fi, hotkey or other setting. Switch an app off to leave it out.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                SettingsGroup {
                    ForEach(entries, id: \.id) { entry in
                        SettingsToggleRow(
                            Text(verbatim: AutomationDescription.applicationName(for: entry.id)),
                            isOn: isIncluded(entry.id),
                            small: Text(verbatim: entry.id)
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
                Button("Save…") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.count == excluded.count)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 480)
        .onAppear {
            entries = SharedProfile.applications(
                itemSections: profile.itemSections,
                applicationSections: profile.applicationSections,
                knownApplications: profile.knownApplications,
                ownBundleIdentifier: Constants.bundleIdentifier
            )
        }
    }

    private func isIncluded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(id) },
            set: { isOn in
                if isOn {
                    excluded.remove(id)
                } else {
                    excluded.insert(id)
                }
            }
        )
    }

    private func save() {
        let shared = SharedProfile(name: profile.name, apps: entries.filter { !excluded.contains($0.id) })
        guard let data = shared.encoded() else {
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(SharedProfile.cleanedName(profile.name)).holzbarprofile"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try? data.write(to: url, options: .atomic)
        dismiss()
    }
}
