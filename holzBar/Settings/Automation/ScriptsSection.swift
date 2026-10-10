//
//  ScriptsSection.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The scripts of the scripts folder: the folder the user chose, what each script is, the
/// user's approval of its exact content, how it last ran and how long it may run. A script runs
/// only after an approval; a changed file needs a new one.
struct ScriptsSection: View {
    let store: ScriptStore
    let manager: AutomationManager
    @State private var pending: Confirmation?

    /// What the open sheet asks the user to confirm.
    private enum Confirmation: Identifiable {
        case allow(ScriptStore.Entry)
        case folder(URL)

        var id: String {
            switch self {
            case .allow(let entry): "allow:\(entry.name):\(entry.sha256)"
            case .folder(let url): "folder:\(url.path(percentEncoded: false))"
            }
        }
    }

    var body: some View {
        HolzBarSection {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Scripts")
                    .font(.headline)
                PreviewBadge()
            }
        } content: {
            Text("Scripts run as you, with holzBar's permissions. macOS asks separately before a script controls another app. Only scripts in the folder you chose run, and only after you allowed their exact content.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            folderRow
            ForEach(store.scripts) { entry in
                row(for: entry)
            }
            HStack {
                Button("Check Now") {
                    manager.checkScriptsNow()
                }
                Spacer()
            }
        }
        .onAppear {
            store.refresh()
        }
        .sheet(item: $pending) { confirmation in
            sheet(for: confirmation)
        }
    }

    // MARK: Folder

    private var folderRow: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            Label {
                Text(verbatim: Self.shortenedPath(of: store.folderURL))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder")
            }
            if let refusal = store.folderRefusal {
                notice(refusalText(refusal))
            }
            if let problem = store.problem {
                notice(problemText(problem))
            }
            HStack {
                Button("Choose Folder…") {
                    chooseFolder()
                }
                Button("Open Scripts Folder") {
                    store.openFolder()
                }
                Spacer()
            }
        }
    }

    /// The path of a folder as one line: the home folder as "~", and every name cleaned and
    /// shortened, because a folder name is text from outside holzBar (T-11-L2).
    private static func shortenedPath(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let shown = if path == home {
            "~"
        } else if path.hasPrefix(home + "/") {
            "~" + String(path.dropFirst(home.count))
        } else {
            path
        }
        return shown
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0 == "~" ? "~" : URLPrompt.displayName(String($0)) }
            .joined(separator: "/")
    }

    /// Asks for a folder. The folder is used only after the user confirmed, because every
    /// approval is removed with it.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.folderURL
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let chosen = url.standardizedFileURL.path(percentEncoded: false)
        guard chosen != store.folderURL.standardizedFileURL.path(percentEncoded: false) else {
            return
        }
        pending = .folder(url)
    }

    private func notice(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(HolzBarTheme.Typography.caption)
        .foregroundStyle(HolzBarTheme.Palette.warning)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refusalText(_ refusal: ScriptGate.FolderRefusal) -> Text {
        switch refusal {
        case .symbolicLink: Text("This folder is a link, so no script in it runs.")
        case .notDirectory: Text("This is not a folder, so no script runs.")
        case .notOwnedByUser: Text("This folder is not yours, so no script in it runs.")
        case .writableByOthers: Text("Others can write to this folder, so no script in it runs.")
        }
    }

    private func problemText(_ problem: ScriptStore.Problem) -> Text {
        switch problem {
        case .newerVersion: Text("Your scripts were set up by a newer holzBar. Nothing runs until you update holzBar.")
        case .setAside: Text("The scripts file could not be read and was set aside. Allow your scripts again.")
        }
    }

    // MARK: Confirmation

    @ViewBuilder
    private func sheet(for confirmation: Confirmation) -> some View {
        switch confirmation {
        case .allow(let entry):
            ConfirmSheet(
                title: Text("Allow this script?"),
                message: Text(verbatim: approvalMessage(for: entry)),
                confirmTitle: "Allow",
                cancelTitle: "Cancel",
                isDestructive: true,
                onConfirm: {
                    pending = nil
                    store.approve(entry)
                },
                onCancel: {
                    pending = nil
                }
            )
        case .folder(let url):
            ConfirmSheet(
                title: Text("Use this folder for scripts?"),
                message: Text("Every approval is removed. Each script in the new folder needs your approval again."),
                confirmTitle: "Use Folder",
                cancelTitle: "Cancel",
                isDestructive: true,
                onConfirm: {
                    pending = nil
                    store.setFolder(url)
                },
                onCancel: {
                    pending = nil
                }
            )
        }
    }

    /// What the sheet says about a script, in fixed wording around the file's name, its folder,
    /// its size and the start of its checksum. The names are cleaned and shortened, and the text
    /// is shown as it is, never as markup (T-11-L2).
    private func approvalMessage(for entry: ScriptStore.Entry) -> String {
        let name = URLPrompt.displayName(entry.name)
        let folder = URLPrompt.displayName(store.folderURL.lastPathComponent)
        return String(
            localized: "\u{201C}\(name)\u{201D} in the folder \u{201C}\(folder)\u{201D}, \(entry.size) bytes, checksum starts with \(entry.checksumPrefix). It runs as you, with holzBar's permissions, including Accessibility. macOS asks separately before it controls another app. Allow it only if you wrote it or read it."
        )
    }

    // MARK: Scripts

    private func row(for entry: ScriptStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: URLPrompt.displayName(entry.name))
                    statusText(for: entry.decision)
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
                Spacer()
                switch entry.decision {
                case .needsApproval:
                    Button("Allow…") {
                        pending = .allow(entry)
                    }
                case .allowed:
                    Button("Remove Approval") {
                        store.revokeApproval(entry)
                    }
                case .refused:
                    EmptyView()
                }
            }
            if case .allowed = entry.decision {
                lastRun(of: entry)
                HStack {
                    ScriptTimeLimitStepper(store: store, name: entry.name)
                        .id(store.folderURL)
                    Spacer()
                }
            }
        }
    }

    /// How the script last ran in this session, and the first line it printed. The line is
    /// text from the script: it is shown as it is on one line, never as a link, markup or a
    /// styled string (D-08, T-11-M3).
    @ViewBuilder
    private func lastRun(of entry: ScriptStore.Entry) -> some View {
        if let record = manager.lastScriptRuns[entry.name] {
            VStack(alignment: .leading, spacing: 2) {
                lastRunText(for: record.termination)
                if !record.displayLine.isEmpty {
                    Text(verbatim: record.displayLine)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        }
    }

    private func lastRunText(for termination: ScriptTermination) -> Text {
        switch termination {
        case .exited(0): Text("Last run: succeeded")
        case .exited: Text("Last run: failed")
        case .signaled: Text("Last run: stopped by a signal")
        case .timedOut: Text("Last run: timed out")
        case .notLaunched: Text("Last run: could not start")
        }
    }

    private func statusText(for decision: ScriptGate.Decision) -> Text {
        switch decision {
        case .allowed: Text("Allowed")
        case .needsApproval: Text("Needs your approval")
        case .refused(.badName): Text("Not a plain file name")
        case .refused(.notRegularFile): Text("Not a regular file")
        case .refused(.symbolicLink): Text("A link, not a file")
        case .refused(.notOwnedByUser): Text("Not owned by you")
        case .refused(.writableByOthers): Text("Others can write to it")
        case .refused(.quarantined): Text("Downloaded: remove the quarantine first")
        case .refused(.tooLarge): Text("Too large")
        case .refused(.notExecutable): Text("Not executable")
        }
    }
}

/// The time limit of one script, from 1 to 60 seconds. The value is kept here while the
/// stepper is used, and written to the store when it changes (D-07).
private struct ScriptTimeLimitStepper: View {
    let store: ScriptStore
    let name: String
    @State private var seconds: Int

    init(store: ScriptStore, name: String) {
        self.store = store
        self.name = name
        _seconds = State(initialValue: store.timeLimit(for: name))
    }

    var body: some View {
        Stepper(
            "Time limit: \(seconds) s",
            value: $seconds,
            in: ScriptLimits.minimumTimeLimit...ScriptLimits.maximumTimeLimit
        )
        .fixedSize()
        .onChange(of: seconds) { _, newValue in
            store.setTimeLimit(newValue, for: name)
        }
    }
}
