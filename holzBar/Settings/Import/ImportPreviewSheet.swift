//
//  ImportPreviewSheet.swift
//  holzBar
//

import SwiftUI

/// The two-step sheet that brings another app's settings into holzBar: first the choice of the
/// source, then a preview of every setting that would change. Nothing is read before the user
/// presses "Preview Import", and nothing is written before "Import Settings".
struct ImportPreviewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the sheet is busy with.
    private enum Activity {
        case idle
        case reading
        case applying
    }

    /// What went wrong last; the sheet stays on its step.
    private enum Failure {
        case unreadable
        case applyFailed
    }

    /// The controls that can hold the focus.
    private enum Control: Hashable {
        case previewImport
        case importSettings
    }

    /// One row of the list of changes.
    private struct ChangeRow: Identifiable {
        let id: String
        let label: String
        let before: String
        let after: String
        let isComposite: Bool
    }

    /// The plan the preview shows; the sheet is on its second step while there is one.
    @State private var plan: ImportPlan?
    @State private var activity = Activity.idle
    @State private var failure: Failure?
    /// Whether the source is installed, found by its bundle identifier when the sheet opens.
    @State private var isInstalled = PreviousAppImporter.isInstalled(.thaw)
    @FocusState private var focus: Control?

    var body: some View {
        Group {
            if let plan {
                previewStep(plan)
            } else {
                sourceStep
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: DesignTokens.ImportSheet.width)
        .background(HolzBarTheme.Palette.ground)
        .interactiveDismissDisabled(activity == .applying)
        .onExitCommand {
            if activity != .applying {
                dismiss()
            }
        }
        .onAppear {
            focus = plan == nil ? .previewImport : .importSettings
        }
    }

    // MARK: Step 1: the source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            title(Text("Import from Another App"))
            SettingsGroup(
                SettingsCatalog.ImportSheet.apps,
                footnote: Text("Window sizes, item positions and scripts are never imported.")
            ) {
                SettingsButtonRow(
                    Text(verbatim: ImportSource.thaw.productName),
                    small: isInstalled ? Text("Found") : Text("Not found")
                ) {
                    if activity == .reading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Preview Import") {
                            preview(.thaw)
                        }
                        .focused($focus, equals: .previewImport)
                        .disabled(!isInstalled)
                    }
                }
            }
            if activity == .reading {
                SettingsGroup {
                    SettingsStateLine(.info, Text("Reading settings…"))
                }
            } else if failure == .unreadable {
                SettingsGroup {
                    SettingsStateLine(.warning, Text("The settings could not be read. Choose a settings file instead."))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Step 2: the preview

    private func previewStep(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            title(Text("Import from \(plan.source.productName)"))
            SettingsGroup {
                SettingsStateLine(.info, Text("\(plan.changes.count) settings will change"))
                if plan.ignoredCount > 0 {
                    SettingsStateLine(.info, Text("\(plan.ignoredCount) other settings are ignored"))
                }
            }
            ScrollView {
                SettingsGroup(SettingsCatalog.ImportSheet.changes) {
                    ForEach(rows(for: plan)) { row in
                        if row.isComposite {
                            SettingsChangeRow(compositeLabel: row.label)
                        } else {
                            SettingsChangeRow(row.label, before: row.before, after: row.after)
                        }
                    }
                }
            }
            .frame(
                minHeight: DesignTokens.ImportSheet.listMinHeight,
                maxHeight: DesignTokens.ImportSheet.listMaxHeight
            )
            SettingsGroup {
                SettingsStateLine(.info, Text("holzBar makes a backup first and restarts to apply them."))
                if failure == .applyFailed {
                    SettingsStateLine(.warning, Text("The settings could not be imported."))
                }
            }
            HStack {
                Button("Back") {
                    goBack()
                }
                .disabled(activity == .applying)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(activity == .applying)
                if activity == .applying {
                    HStack(spacing: HolzBarTheme.Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing…")
                            .font(HolzBarTheme.Typography.body)
                            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    }
                } else {
                    Button("Import Settings") {
                        apply(plan)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .focused($focus, equals: .importSettings)
                    .disabled(plan.changes.isEmpty)
                }
            }
        }
    }

    /// The sheet's title with the Preview badge 8 pt after it.
    private func title(_ text: Text) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            text
                .font(HolzBarTheme.Typography.title)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            PreviewBadge()
        }
    }

    // MARK: Actions

    /// The changes in the order of the Settings window, each with the name its row has there.
    private func rows(for plan: ImportPlan) -> [ChangeRow] {
        plan.changes
            .sorted { ImportTargets.sortIndex(of: $0.key) < ImportTargets.sortIndex(of: $1.key) }
            .compactMap { change in
                guard let entry = ImportTargets.entry(for: change.key) else {
                    return nil
                }
                return ChangeRow(
                    id: change.key.rawValue,
                    label: entry.label,
                    before: ImportTargets.text(for: change.before, of: change.key),
                    after: ImportTargets.text(for: change.after, of: change.key),
                    isComposite: change.after == .composite
                )
            }
    }

    private var stepAnimation: Animation {
        HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    /// Reads the source's settings, only after the click, and moves to the preview.
    private func preview(_ source: ImportSource) {
        failure = nil
        activity = .reading
        Task {
            // Let the spinner draw before the read.
            await Task.yield()
            guard let domain = PreviousAppImporter.readDomain(of: source) else {
                activity = .idle
                failure = .unreadable
                return
            }
            let planned = PreviousAppImporter.plan(for: source, settings: domain, appState: appState)
            activity = .idle
            withAnimation(stepAnimation) {
                plan = planned
            }
            focus = .importSettings
        }
    }

    private func goBack() {
        failure = nil
        withAnimation(stepAnimation) {
            plan = nil
        }
        focus = .previewImport
    }

    /// Writes the backup and the settings and restarts holzBar. The sheet stays until the app
    /// quits, or shows the failure and gives the primary back.
    private func apply(_ plan: ImportPlan) {
        failure = nil
        activity = .applying
        Task {
            await Task.yield()
            do {
                try PreviousAppImporter.apply(plan)
            } catch {
                activity = .idle
                failure = .applyFailed
            }
        }
    }
}
