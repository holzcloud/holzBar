//
//  UsageSuggestionsSection.swift
//  holzBar
//

import SwiftUI

/// Suggestions to hide items that were not opened for two weeks, from counters that stay on
/// this Mac. The feature is off until the user turns it on; the section says exactly what is
/// stored, shows it, and forgets it in one click.
struct UsageSuggestionsSection: View {
    @Environment(AppState.self) private var appState
    @Bindable var usage: UsageStore
    @State private var isShowingData = false
    @State private var isConfirmingForget = false
    @State private var isConfirmingTurnOff = false
    /// Whether the tidy-up suggestion was answered; kept here so its line goes at once.
    @State private var wasTidyUpAnswered = Defaults.bool(forKey: .cleanUpOffered)

    var body: some View {
        let summary = usage.counters.summary
        SettingsGroup(SettingsCatalog.LayoutPane.suggestions) {
            tidyUpLine
            SettingsToggleRow(.layoutSuggestRarelyUsed, isOn: suggestionsBinding)
            if usage.isEnabled {
                ForEach(usage.suggestions, id: \.windowID) { item in
                    SettingsButtonRow(Text("You have not opened \(item.displayName) in 14 days.")) {
                        Button("Move to Hidden") {
                            usage.hide(item)
                        }
                        Button("Keep") {
                            usage.keep(item)
                        }
                    }
                }
            }
            SettingsButtonRow(.layoutStoredUsage, small: Text("\(summary.items) items, \(summary.clicks) opens")) {
                Button("View Data…") {
                    isShowingData = true
                }
            }
            .settingsDependent(on: usage.isEnabled)
            SettingsButtonRow {
                Button("Forget everything…", role: .destructive) {
                    isConfirmingForget = true
                }
            }
            .settingsDependent(on: usage.isEnabled)
        }
        .sheet(isPresented: $isShowingData) {
            UsageDataSheet(usage: usage)
        }
        .holzBarConfirmation(
            isPresented: $isConfirmingForget,
            title: Text("Forget all stored usage?"),
            message: Text("The counts of every item are deleted. This cannot be undone."),
            confirmTitle: "Forget Everything",
            isDestructive: true
        ) {
            usage.forgetEverything()
        }
        .holzBarConfirmation(
            isPresented: $isConfirmingTurnOff,
            title: Text("Turn off suggestions and forget the stored usage?"),
            message: Text("The counts of every item are deleted. This cannot be undone."),
            confirmTitle: "Turn Off and Forget",
            isDestructive: true
        ) {
            usage.isEnabled = false
        }
    }

    /// Turning the suggestions off deletes the stored usage, so it asks first while there is
    /// some, as Forget everything… does (audit-ux A16).
    private var suggestionsBinding: Binding<Bool> {
        Binding(
            get: { usage.isEnabled },
            set: { isOn in
                if !isOn, usage.counters.summary.items > 0 {
                    isConfirmingTurnOff = true
                } else {
                    usage.isEnabled = isOn
                }
            }
        )
    }

    /// The tidy-up suggestion as one line, in place of the old alert after launch (D-21). The
    /// proposals are read only while the line can show, so a Mac that answered pays nothing.
    @ViewBuilder
    private var tidyUpLine: some View {
        if !wasTidyUpAnswered, !appState.didImportPreviousSettings, appState.profiles.profiles.isEmpty {
            let visibleCount = appState.itemManager.itemCache[.visible].filter { !$0.isControlItem }.count
            let count = visibleCount >= TidyUpSuggestionPolicy.minimumVisibleItems
                ? TidyUpEntry.proposals(from: appState).count
                : 0
            if TidyUpSuggestionPolicy.showsLine(
                wasOffered: wasTidyUpAnswered,
                hasImportedSettings: appState.didImportPreviousSettings,
                hasProfiles: !appState.profiles.profiles.isEmpty,
                visibleItemCount: visibleCount,
                proposalCount: count
            ) {
                SettingsButtonRow(
                    Text("holzBar suggests hiding \(count) items."),
                    info: Text("holzBar suggests what works in the background; the clock, the battery and apps with messages stay. Nothing leaves your Mac, you decide, and you can undo it.")
                ) {
                    Button("View…") {
                        answerTidyUp()
                        appState.navigationState.isTidyUpPresented = true
                    }
                    Button("Not Now") {
                        answerTidyUp()
                    }
                }
            }
        }
    }

    private func answerTidyUp() {
        Defaults.set(true, forKey: .cleanUpOffered)
        wasTidyUpAnswered = true
    }
}

/// Everything the counters hold: each item and its opens on each of the last 30 days.
private struct UsageDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    let usage: UsageStore
    @State private var isConfirmingForget = false

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
                Button("Forget everything…", role: .destructive) {
                    isConfirmingForget = true
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
        .holzBarConfirmation(
            isPresented: $isConfirmingForget,
            title: Text("Forget all stored usage?"),
            message: Text("The counts of every item are deleted. This cannot be undone."),
            confirmTitle: "Forget Everything",
            isDestructive: true
        ) {
            usage.forgetEverything()
            dismiss()
        }
    }
}
