//
//  LaunchAtLoginToggle.swift
//  holzBar
//

import OSLog
import ServiceManagement
import SwiftUI

/// The "Launch at login" toggle, backed by `SMAppService.mainApp`.
///
/// It is the same registration the LaunchAtLogin-Modern package made, so a user's
/// setting carries over. The toggle always shows the real status, which the user may
/// also change in System Settings › General › Login Items.
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
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: isEnabled)
            if status == .requiresApproval {
                HStack {
                    Text("Allow holzBar in System Settings to launch it at login.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            refresh()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                refresh()
            }
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
