//
//  AdvancedImportRows.swift
//  holzBar
//

import SwiftUI

/// The rows of the Back up group that bring settings in from another app: the button that opens
/// the import sheet and, while the backup of an import exists, the row that puts the earlier
/// settings back. The import is always the user's own click; holzBar reads no other app's
/// settings at launch.
struct AdvancedImportRows: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingSheet = false
    @State private var isConfirmingRestore = false
    /// The record of the settings before the last import, read when the rows appear and when the
    /// sheet closes (no observer, no timer); `nil` while there is none.
    @State private var lastImport: ImportBackupRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsButtonRow(unlabeled: .advancedImportFromApp, badge: .preview) {
                Button("Import from Another App…") {
                    isShowingSheet = true
                }
            }
            if let record = lastImport {
                restoreRow(for: record)
            }
        }
        .onAppear {
            lastImport = PreviousAppImporter.lastImport()
        }
        .sheet(isPresented: $isShowingSheet) {
            lastImport = PreviousAppImporter.lastImport()
        } content: {
            ImportPreviewSheet()
                .environment(appState)
        }
    }

    /// The row that exists only while a backup does: its button asks first, because changes made
    /// since the import are lost.
    private func restoreRow(for record: ImportBackupRecord) -> some View {
        SettingsButtonRow(.advancedRestoreBeforeImport, small: Text(verbatim: record.source.productName), badge: .preview) {
            Button("Restore Settings Before Import…") {
                isConfirmingRestore = true
            }
        }
        .holzBarConfirmation(
            isPresented: $isConfirmingRestore,
            title: Text("Restore the settings from before the import?"),
            message: Text("holzBar goes back to the settings it had before you imported from \(record.source.productName) on \(record.date.formatted(date: .long, time: .omitted)). Changes made since then are lost. holzBar restarts."),
            confirmTitle: "Restore and Restart",
            isDestructive: true
        ) {
            PreviousAppImporter.restore(record)
        }
    }
}
