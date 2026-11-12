//
//  LiveActivitiesSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Live activities module's settings, in the open area of the module's row: one switch per
/// source, their explanations in the popovers.
///
/// The camera and microphone switch exists only on macOS 14.2 and later, where the listeners
/// are. The Downloads switch is the one that asks macOS for the Downloads folder; a refusal shows
/// a state line with a way to System Settings, and nothing asks again by itself. The view only
/// flips stored switches and reads the access state of the running runtime. A note line says that
/// the module is holzBar's own and unrelated to Apple's Live Activities from the iPhone.
struct LiveActivitiesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.liveActivities
        if #available(macOS 14.2, *) {
            SettingsToggleRow(
                .modulesLiveActivitiesCapture,
                isOn: $settings.capturesInUse,
                small: Text("from macOS 14.2")
            )
        }
        SettingsToggleRow(.modulesLiveActivitiesDownloads, isOn: $settings.watchesDownloads)
        if settings.watchesDownloads, downloadsAccess == .denied {
            SettingsStateLine(.warning, Text("Downloads access is off")) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        SettingsNoteLine(Text("These are holzBar's own activities, not Apple's Live Activities from your iPhone."))
    }

    /// What macOS lets holzBar do with the Downloads folder, as the running runtime last found.
    /// `unknown` while the runtime does not exist (the hub is off) or the source is off.
    private var downloadsAccess: DownloadsSource.Access {
        appState.notchHub.runtime(LiveActivitiesRuntime.self)?.downloadsAccess ?? .unknown
    }
}
