//
//  ImportPreviewSheet.swift
//  holzBar
//

import AppKit
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
        /// The chosen file is not a settings file of either app.
        case unusableFile
        /// The record of the previous settings could not be written, so nothing was imported.
        case backupFailed
        case applyFailed
    }

    /// The controls that can hold the focus.
    private enum Control: Hashable {
        /// The first source's button, which has the focus when the sheet opens.
        case previewImport
        case previewHiddenBar
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
    /// The source being read: its row shows the spinner while the sheet is reading. While it is
    /// `nil` and the sheet is reading, the file the user chose is being read.
    @State private var readingSource: ImportSource?
    /// Which apps are installed, found by their bundle identifiers when the sheet opens.
    @State private var installed = Dictionary(
        uniqueKeysWithValues: ImportSource.allCases.map { ($0, PreviousAppImporter.isInstalled($0)) }
    )
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
                ForEach(ImportSource.allCases, id: \.self) { source in
                    sourceRow(source)
                }
            }
            // Whatever the detection of the two apps says, a settings file is always a way in: a
            // build with another bundle identifier shows as not found.
            SettingsGroup {
                SettingsButtonRow(
                    Text("Settings file"),
                    info: Text("Use this for a settings file you exported or that holzBar cannot see.")
                ) {
                    if activity == .reading, readingSource == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Choose File…") {
                            chooseFile()
                        }
                        .disabled(activity == .reading)
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
            } else if failure == .unusableFile {
                SettingsGroup {
                    SettingsStateLine(.warning, Text("That file has no settings holzBar can use. Choose another file."))
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

    /// One app: whether it is installed and the button that reads its settings.
    private func sourceRow(_ source: ImportSource) -> some View {
        let isInstalled = installed[source] ?? false
        return SettingsButtonRow(
            Text(verbatim: source.productName),
            small: isInstalled ? Text("Found") : Text("Not found")
        ) {
            if activity == .reading, readingSource == source {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Preview Import") {
                    preview(source)
                }
                .focused($focus, equals: source == .hiddenBar ? Control.previewHiddenBar : Control.previewImport)
                .disabled(!isInstalled || activity == .reading)
            }
        }
    }

    // MARK: Step 2: the preview

    private func previewStep(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            title(Text("Import from \(plan.source.productName)"))
            if !plan.changes.isEmpty || plan.ignoredCount > 0 {
                SettingsGroup {
                    // With nothing to change the empty state below says so, not a count of zero.
                    if !plan.changes.isEmpty {
                        SettingsStateLine(.info, Text("\(plan.changes.count) settings will change"))
                    }
                    if plan.ignoredCount > 0 {
                        SettingsStateLine(.info, Text("\(plan.ignoredCount) other settings are ignored"))
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
                    if plan.changes.isEmpty {
                        EmptyState(
                            systemImage: "checkmark.circle",
                            title: Text("Nothing to change"),
                            message: Text("holzBar already has these settings."),
                            isCompact: true
                        )
                    } else {
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
                    if !plan.omissions.isEmpty {
                        SettingsGroup(SettingsCatalog.ImportSheet.notImported) {
                            ForEach(plan.omissions) { omission in
                                SettingsValueRow(
                                    Text(ImportTargets.omissionLabel(for: omission)),
                                    value: Text("Not imported")
                                )
                            }
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
                if failure == .backupFailed {
                    SettingsStateLine(
                        .warning,
                        Text("The backup could not be made, so nothing was imported. Free up disk space and try again.")
                    )
                } else if failure == .applyFailed {
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
            .sorted { ImportTargets.sortIndex(of: $0) < ImportTargets.sortIndex(of: $1) }
            .compactMap { change in
                guard let entry = ImportTargets.entry(for: change) else {
                    return nil
                }
                return ChangeRow(
                    // A hotkey change shares the key of every other, so its action names it.
                    id: change.hotkeyAction ?? change.key.rawValue,
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
        readingSource = source
        activity = .reading
        Task {
            // Let the spinner draw before the read.
            await Task.yield()
            guard let domain = PreviousAppImporter.readDomain(of: source) else {
                activity = .idle
                failure = .unreadable
                return
            }
            show(PreviousAppImporter.plan(for: source, settings: domain, appState: appState))
        }
    }

    /// Asks for a settings file, reads it and moves to the preview of the app its keys name.
    ///
    /// The panel starts where macOS puts it and holzBar never points it into another app's folder;
    /// only the file the user picks is read, as a size-limited regular local file.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        failure = nil
        readingSource = nil
        activity = .reading
        Task {
            // Let the spinner draw before the read.
            await Task.yield()
            do {
                let settings = try PreviousAppImporter.readFile(at: url)
                guard let source = PreviousAppImport.recognize(settings) else {
                    activity = .idle
                    failure = .unusableFile
                    return
                }
                show(PreviousAppImporter.plan(for: source, settings: settings, appState: appState))
            } catch PreviousAppImporter.ImportError.unusableFile {
                activity = .idle
                failure = .unusableFile
            } catch {
                activity = .idle
                failure = .unreadable
            }
        }
    }

    /// Moves to the preview of a plan.
    private func show(_ planned: ImportPlan) {
        activity = .idle
        withAnimation(stepAnimation) {
            plan = planned
        }
        focus = .importSettings
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
            } catch PreviousAppImporter.ImportError.backupFailed {
                // Nothing was written: the primary comes back, and the user can try again.
                activity = .idle
                failure = .backupFailed
            } catch {
                activity = .idle
                failure = .applyFailed
            }
        }
    }
}
