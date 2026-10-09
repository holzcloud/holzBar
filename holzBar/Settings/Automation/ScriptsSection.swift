//
//  ScriptsSection.swift
//  holzBar
//

import SwiftUI

/// The scripts of the Scripts folder: what each is, and the user's approval of its exact
/// content. A script runs only after an approval; a changed file needs a new one.
struct ScriptsSection: View {
    let store: ScriptStore
    let manager: AutomationManager
    @State private var approving: ScriptStore.Entry?

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { approving != nil },
            set: { isPresented in
                if !isPresented {
                    approving = nil
                }
            }
        )
    }

    var body: some View {
        HolzBarSection("Scripts") {
            Text("Scripts run as you, with holzBar's permissions, and only after you allowed their exact content. Put them in the Scripts folder; nothing else can run.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.scripts) { entry in
                row(for: entry)
            }
            HStack {
                Button("Open Scripts Folder") {
                    store.openFolder()
                }
                Button("Check Now") {
                    manager.checkScriptsNow()
                }
                Spacer()
            }
        }
        .onAppear {
            store.refresh()
        }
        .confirmationDialog("Allow this script?", isPresented: isConfirming, titleVisibility: .visible, presenting: approving) { entry in
            Button("Allow") {
                store.approve(entry)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("\(entry.name), \(entry.size) bytes, checksum starts with \(entry.checksumPrefix). It runs as you, with holzBar's permissions. Allow it only if you wrote it or read it.")
        }
    }

    private func row(for entry: ScriptStore.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                statusText(for: entry.decision)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            Spacer()
            switch entry.decision {
            case .needsApproval:
                Button("Allow…") {
                    approving = entry
                }
            case .allowed:
                Button("Remove Approval") {
                    store.revokeApproval(entry)
                }
            case .refused:
                EmptyView()
            }
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
