//
//  LaunchAtLoginToggle.swift
//  holzBar
//

import OSLog
import ServiceManagement
import SwiftUI

/// The "Launch at login" rows of the Startup group, backed by `SMAppService.mainApp`.
///
/// It is the same registration the LaunchAtLogin-Modern package made, so a user's setting
/// carries over. The switch always shows the real status, which the user may also change in
/// System Settings › General › Login Items; while macOS waits for the user's approval, a sub row
/// opens that place.
struct LaunchAtLoginToggle: View {
    private static let logger = Logger(category: "LaunchAtLogin")

    @State private var status = SMAppService.mainApp.status

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { status == .enabled },
            set: { setEnabled($0) }
        )
    }

    var body: some View {
        SettingsToggleRow(.generalLaunchAtLogin, isOn: isEnabled)
            .onAppear {
                refresh()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                    refresh()
                }
            }
        if status == .requiresApproval {
            SettingsButtonRow(.generalAllowLoginItem) {
                Button("Open System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            .settingsSubRow()
        }
    }

    private func refresh() {
        status = SMAppService.mainApp.status
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Could not change launch at login: \(error, privacy: .private)")
        }
        refresh()
    }
}
