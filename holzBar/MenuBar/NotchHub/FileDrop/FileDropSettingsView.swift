//
//  FileDropSettingsView.swift
//  holzBar
//

import SwiftUI

/// The File drop module's settings, in the open area of the module's row: whether a file dragged
/// to the notch opens the hub, and whether a file leaves the stash after it was dropped
/// elsewhere. The explanations are in the rows' popovers; the view only flips stored switches.
struct FileDropSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.fileDrop
        SettingsToggleRow(.modulesFileDropOpensOnDrag, isOn: $settings.opensOnDrag)
        SettingsToggleRow(.modulesFileDropRemovesAfterDrop, isOn: $settings.removesAfterDrop)
    }
}
