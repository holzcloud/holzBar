//
//  FileDropSettingsView.swift
//  holzBar
//

import SwiftUI

/// The File drop module's settings, shown under its row in the Modules pane while the module is
/// on: whether a file dragged to the notch opens the hub, and whether a file leaves the stash
/// after it was dropped elsewhere. The view only flips stored switches.
struct FileDropSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.fileDrop
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Open when you drag a file to the notch", isOn: $settings.opensOnDrag)
            caption(Text("The pointer has to rest at the notch while you drag."))
            Toggle("Remove a file from the stash after you dropped it", isOn: $settings.removesAfterDrop)
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
