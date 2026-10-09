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

    private var isConfirmingRestore: Binding<Bool> {
        Binding(
            get: { restoreTarget != nil },
            set: { isPresented in
                if !isPresented {
                    restoreTarget = nil
                }
            }
        )
    }

    var body: some View {
        HolzBarSection("Layout History") {
            Toggle("Keep a history of the layout", isOn: $snapshots.isEnabled)
            if !isDismissed, let suggested = snapshots.snapshotToSuggest {
                suggestion(for: suggested)
            }
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
        }
        .confirmationDialog("Restore this layout?", isPresented: isConfirmingRestore, titleVisibility: .visible, presenting: restoreTarget) { target in
            Button("Restore") {
                snapshots.restore(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let diff = snapshots.diff(to: target)
            Text("\(diff.moves) items will move, \(diff.notPresent) are not in the menu bar now. The layout as it is now is kept first, so you can undo this.")
        }
        .confirmationDialog("Delete all snapshots?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All Snapshots", role: .destructive) {
                snapshots.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
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
    }

    private func reasonText(_ reason: SnapshotReason) -> String {
        switch reason {
        case .settled: String(localized: "After the bar settled")
        case .daily: String(localized: "First check of the day")
        case .beforeProfile: String(localized: "Before a profile")
        case .beforeRestore: String(localized: "Before a restore")
        case .beforeAssistant: String(localized: "Before tidying up")
        case .manual: String(localized: "Taken by you")
        }
    }
}
