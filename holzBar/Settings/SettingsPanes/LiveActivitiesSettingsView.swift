//
//  LiveActivitiesSettingsView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Live activities module's settings, shown under its row in the Modules pane while the
/// module is on: one switch per source.
///
/// The camera and microphone switch exists only on macOS 14.2 and later, where the listeners
/// are. The Downloads switch is the one that asks macOS for the Downloads folder, so its line
/// says so, and a refusal is explained here with a way to System Settings; nothing asks again by
/// itself. The view only flips stored switches and reads the access state of the running
/// runtime. The module is holzBar's own and unrelated to Apple's Live Activities from the
/// iPhone, which the Advanced pane's setting looks after.
struct LiveActivitiesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.liveActivities
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            if #available(macOS 14.2, *) {
                Toggle("Camera and microphone in use", isOn: $settings.capturesInUse)
                caption(Text("A capsule shows while another app uses the camera or the microphone. holzBar reads no audio or video."))
            }
            Toggle("Downloads", isOn: $settings.watchesDownloads)
            caption(Text("Asks for access to your Downloads folder when you switch it on. holzBar never reads what you download."))
            if settings.watchesDownloads, downloadsAccess == .denied {
                deniedAccess
            }
            caption(Text("These are holzBar's own activities, not Apple's Live Activities from your iPhone."))
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    /// What macOS lets holzBar do with the Downloads folder, as the running runtime last found.
    /// `unknown` while the runtime does not exist (the hub is off) or the source is off.
    private var downloadsAccess: DownloadsSource.Access {
        appState.notchHub.runtime(LiveActivitiesRuntime.self)?.downloadsAccess ?? .unknown
    }

    /// The sentence and the button of a refused folder; nothing asks by itself.
    private var deniedAccess: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Text("Downloads access is off")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
