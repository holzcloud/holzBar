//
//  AdvancedImportRows.swift
//  holzBar
//

import SwiftUI

/// The rows of the Back up group that bring settings in from another app: the button that opens
/// the import sheet. The import is always the user's own click; holzBar reads no other app's
/// settings at launch.
struct AdvancedImportRows: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingSheet = false

    var body: some View {
        SettingsButtonRow(unlabeled: .advancedImportFromApp, badge: .preview) {
            Button("Import from Another App…") {
                isShowingSheet = true
            }
        }
        .sheet(isPresented: $isShowingSheet) {
            ImportPreviewSheet()
                .environment(appState)
        }
    }
}
