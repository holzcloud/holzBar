//
//  MenuBarItemsLoadingState.swift
//  holzBar
//

import SwiftUI

/// "Loading menu bar items…" that never spins forever: after one deadline it says that holzBar
/// has not read the items yet and offers Read Again (D-26, D-27). It exists only while the
/// items are missing, and runs nothing but that one deadline per attempt.
struct MenuBarItemsLoadingState: View {
    /// Where the state shows.
    enum Style {
        /// A state line in a settings group (Layout).
        case settingsRow
        /// The middle of the search panel.
        case panel
        /// The strip of the holzBar Shelf.
        case strip
    }

    /// How long the reading may take before the state says so.
    static let deadline = Duration.seconds(15)

    let style: Style
    let itemManager: MenuBarItemManager

    @State private var isLate = false
    @State private var attempt = 0

    var body: some View {
        content
            .task(id: attempt) {
                isLate = false
                do {
                    try await Task.sleep(for: Self.deadline)
                } catch {
                    return
                }
                isLate = true
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (style, isLate) {
        case (.settingsRow, false):
            SettingsStateLine(.info, Text("Loading menu bar items…")) {
                ProgressView()
                    .controlSize(.small)
            }
        case (.settingsRow, true):
            SettingsStateLine(.warning, Text("holzBar has not read the menu bar items yet.")) {
                Button("Read Again", action: readAgain)
            }
        case (.panel, false):
            VStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Loading menu bar items…")
                    .font(HolzBarTheme.Typography.title)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.panel, true):
            EmptyState(
                systemImage: "exclamationmark.triangle",
                title: Text("holzBar has not read the menu bar items yet."),
                message: Text("Reading them takes a few seconds. If it does not end, read them again or quit and reopen holzBar."),
                actionTitle: "Read Again",
                action: readAgain
            )
        case (.strip, false):
            HStack {
                Text("Loading menu bar items…")
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
        case (.strip, true):
            HStack {
                Text("holzBar has not read the menu bar items yet.")
                Button("Read Again", action: readAgain)
                    .controlSize(.small)
            }
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
        }
    }

    private func readAgain() {
        let itemManager = itemManager
        Task {
            await itemManager.cacheItemsRegardless()
        }
        attempt += 1
    }
}
