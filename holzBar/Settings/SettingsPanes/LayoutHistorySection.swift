//
//  LayoutHistorySection.swift
//  holzBar
//

import SwiftUI

/// The history of the layout: snapshots to go back to, with a preview of what a restore
/// changes.
struct LayoutHistorySection: View {
    @Bindable var snapshots: LayoutSnapshots
    @State private var restoreTarget: LayoutSnapshot?
    @State private var isDismissed = false
    @State private var isConfirmingDeleteAll = false
    /// The list is folded away until the user opens it.
    @State private var isExpanded = false

    var body: some View {
        HolzBarSection {
            Text("Layout History")
                .font(.headline)
        } content: {
            Toggle("Keep a history of the layout", isOn: $snapshots.isEnabled)
            if snapshots.isEnabled {
                Stepper(value: $snapshots.limit, in: SnapshotRetention.limits) {
                    Text("Snapshots to keep: \(snapshots.limit)")
                }
                .annotation("Older ones are deleted. Starred snapshots stay and are not counted.")
            }
            if !isDismissed, let suggested = snapshots.snapshotToSuggest {
                suggestion(for: suggested)
            }
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(snapshots.snapshots) { snapshot in
                    row(for: snapshot)
                }
                HStack {
                    Button("Take Snapshot Now") {
                        snapshots.take(.manual)
                    }
                    .disabled(!snapshots.isEnabled)
                    Spacer()
                    Button("Delete All Snapshots…", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                    .disabled(snapshots.snapshots.isEmpty)
                }
            } label: {
                Text("Snapshots: \(snapshots.snapshots.count)")
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

    private func suggestion(for snapshot: LayoutSnapshot) -> some View {
        HStack {
            Label("Your layout looks reset.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(HolzBarTheme.Palette.warning)
            Spacer()
            Button("Restore from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))") {
                restoreTarget = snapshot
            }
            Button("Not Now") {
                isDismissed = true
            }
        }
    }

    private func row(for snapshot: LayoutSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                Text("\(reasonText(snapshot.reason)) · Items: \(snapshot.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let starTitle: LocalizedStringKey = snapshot.isStarred ? "Remove Star" : "Star"
            Button(starTitle, systemImage: snapshot.isStarred ? "star.fill" : "star") {
                snapshots.toggleStar(snapshot)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Button("Restore…") {
                restoreTarget = snapshot
            }
            Button("Delete", systemImage: "trash") {
                snapshots.delete(snapshot)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: snapshot.date.formatted(date: .abbreviated, time: .shortened)))
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
