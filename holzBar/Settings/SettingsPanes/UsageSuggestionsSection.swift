//
//  UsageSuggestionsSection.swift
//  holzBar
//

import SwiftUI

/// Suggestions to hide items that were not opened for two weeks, from counters that stay on
/// this Mac. The feature is off until the user turns it on; the section says exactly what is
/// stored, shows it, and forgets it in one click.
struct UsageSuggestionsSection: View {
    @Bindable var usage: UsageStore
    @State private var isShowingData = false

    var body: some View {
        HolzBarSection {
            Text("Usage Suggestions")
                .font(.headline)
        } content: {
            Toggle("Suggest items to hide", isOn: $usage.isEnabled)
                .annotation("Counts how often you open each item, per day for 30 days. The counts stay on this Mac, are not exported or backed up, and are deleted when you turn this off.")
            if usage.isEnabled {
                ForEach(usage.suggestions, id: \.windowID) { item in
                    suggestion(for: item)
                }
                summaryRow
            }
        }
        .sheet(isPresented: $isShowingData) {
            UsageDataSheet(usage: usage)
        }
    }

    private func suggestion(for item: MenuBarItem) -> some View {
        HStack {
            Text("You have not opened \(item.displayName) in 14 days.")
            Spacer()
            Button("Move to Hidden") {
                usage.hide(item)
            }
            Button("Keep") {
                usage.keep(item)
            }
        }
    }

    private var summaryRow: some View {
        let summary = usage.counters.summary
        return HStack {
            Text("\(summary.items) items, \(summary.clicks) opens")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            Spacer()
            Button("View Data…") {
                isShowingData = true
            }
            Button("Forget Everything", role: .destructive) {
                usage.forgetEverything()
            }
        }
    }
}

/// Everything the counters hold: each item and its opens on each of the last 30 days.
private struct UsageDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    let usage: UsageStore

    var body: some View {
        let rows = usage.storedRows()
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Stored Usage")
                .font(.headline)
            Text("Opens per day, oldest first. This is everything holzBar keeps.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            if rows.isEmpty {
                Text("Nothing is stored yet.")
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                        ForEach(rows, id: \.name) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.name)
                                Text(verbatim: row.days.map(String.init).joined(separator: " "))
                                    .font(HolzBarTheme.Typography.monoMicro)
                                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Button("Forget Everything", role: .destructive) {
                    usage.forgetEverything()
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 520)
    }
}
