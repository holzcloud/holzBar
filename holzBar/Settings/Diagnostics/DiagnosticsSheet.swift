//
//  DiagnosticsSheet.swift
//  holzBar
//

import AppKit
import SwiftUI

/// Shows the bug report as it will be copied. Nothing is sent: the user reads it, then
/// copies it into an issue. The pasteboard is written only by a click on a copy button.
struct DiagnosticsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var report: String {
        DiagnosticsReport.make(DiagnosticsCollector.collect(from: appState))
    }

    var body: some View {
        let text = report
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Copy Diagnostics")
                .font(HolzBarTheme.Typography.title)
            Text("Nothing is sent. Read the report, then copy it into your issue. It holds versions and counts only: no names of items, apps, profiles or networks, and no paths.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(verbatim: text)
                    .font(HolzBarTheme.Typography.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HolzBarTheme.Spacing.sm)
            }
            .frame(height: 200)
            .background(HolzBarTheme.Palette.text.opacity(0.05), in: HolzBarTheme.shape(HolzBarTheme.Radius.control))
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Copy") {
                    copy(text)
                    dismiss()
                }
                Button("Copy and Open Issue Tracker") {
                    copy(text)
                    openURL(Constants.issuesURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 520)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
