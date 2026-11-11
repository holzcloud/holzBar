//
//  LayoutHistorySection.swift
//  holzBar
//

import SwiftUI

/// The Layout history group of Profiles & History: snapshots to go back to, with a preview of
/// what a restore changes.
struct LayoutHistorySection: View {
    @Bindable var snapshots: LayoutSnapshots
    @State private var restoreTarget: LayoutSnapshot?
    @State private var isDismissed = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        SettingsGroup(
            SettingsCatalog.ProfilesAndHistoryPane.layoutHistory,
            footnote: Text("holzBar saves the layout by itself before every profile, restore, tidy-up and rule.")
        ) {
            SettingsToggleRow(.profilesKeepHistory, isOn: $snapshots.isEnabled)
            SettingsStepperRow(
                .profilesSnapshotsToKeep,
                value: $snapshots.limit,
                in: SnapshotRetention.limits
            ) { limit in
                Text(limit, format: .number)
            }
            .settingsDependent(on: snapshots.isEnabled)
            if !isDismissed, let suggested = snapshots.snapshotToSuggest {
                SettingsStateLine(.warning, Text("Your layout looks reset."))
                SettingsButtonRow {
                    Button("Restore from \(suggested.date.formatted(date: .abbreviated, time: .shortened))") {
                        restoreTarget = suggested
                    }
                    Button("Not Now") {
                        isDismissed = true
                    }
                }
            }
            SettingsDisclosure(
                Text("Snapshots: \(snapshots.snapshots.count)"),
                id: SettingsCatalog.ProfilesAndHistoryPane.snapshotsDisclosure
            ) {
                ForEach(snapshots.snapshots) { snapshot in
                    row(for: snapshot)
                }
            }
            SettingsButtonRow {
                Button("Take Snapshot Now") {
                    snapshots.take(.manual)
                }
            }
            .settingsDependent(on: snapshots.isEnabled)
            SettingsButtonRow {
                Button("Delete All Snapshots…", role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .disabled(snapshots.snapshots.isEmpty)
            }
        }
        .sheet(item: $restoreTarget) { target in
            let diff = snapshots.diff(to: target)
            ConfirmSheet(
                title: Text("Restore this layout?"),
                message: Text("\(diff.moves) items will move, \(diff.notPresent) are not in the menu bar now. The layout as it is now is kept first, so you can undo this."),
                confirmTitle: "Restore",
                cancelTitle: "Cancel",
                onConfirm: {
                    restoreTarget = nil
                    snapshots.restore(target)
                    AccessibilityNotification.Announcement(
                        String(localized: "Layout restored. The layout before it is kept in Layout History.")
                    ).post()
                },
                onCancel: {
                    restoreTarget = nil
                }
            )
        }
        .holzBarConfirmation(
            isPresented: $isConfirmingDeleteAll,
            title: Text("Delete all snapshots?"),
            confirmTitle: "Delete All Snapshots",
            isDestructive: true
        ) {
            snapshots.deleteAll()
        }
    }

    private func row(for snapshot: LayoutSnapshot) -> some View {
        let date = snapshot.date.formatted(date: .abbreviated, time: .shortened)
        return SettingsButtonRow(
            Text(verbatim: date),
            small: Text("\(reasonText(snapshot.reason)) · Items: \(snapshot.count)")
        ) {
            let starTitle: LocalizedStringKey = snapshot.isStarred ? "Remove Star" : "Star"
            Button(starTitle, systemImage: snapshot.isStarred ? "star.fill" : "star") {
                snapshots.toggleStar(snapshot)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Button("Restore…") {
                restoreTarget = snapshot
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                snapshots.delete(snapshot)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: date))
    }

    private func reasonText(_ reason: SnapshotReason) -> String {
        switch reason {
        case .settled: String(localized: "After the bar settled")
        case .daily: String(localized: "First check of the day")
        case .beforeProfile: String(localized: "Before a profile")
        case .beforeRestore: String(localized: "Before a restore")
        case .beforeAssistant: String(localized: "Before tidying up")
        case .beforeRule: String(localized: "Before a rule")
        case .manual: String(localized: "Taken by you")
        }
    }
}
