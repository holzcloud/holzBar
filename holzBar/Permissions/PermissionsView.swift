//
//  PermissionsView.swift
//  holzBar
//

import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) var appState
    @Environment(AppPermissions.self) var manager

    /// The permissions holzBar asks for at the first launch.
    private var launchPermissions: [Permission] {
        manager.allPermissions.filter { $0.requestsAtLaunch }
    }

    /// The permissions a feature asks for when it is first used.
    private var laterPermissions: [Permission] {
        manager.allPermissions.filter { !$0.requestsAtLaunch }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical)

            permissionsStack

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .frame(width: 550)
        .fixedSize()
    }

    @ViewBuilder
    private var headerView: some View {
        Label {
            Text("Permissions")
                .font(.system(size: 40, weight: .medium))
        } icon: {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 85, height: 85)
            }
        }
    }

    @ViewBuilder
    private var explanationBox: some View {
        HolzBarSection {
            VStack {
                Text("holzBar needs your permission to manage the menu bar.")
                    .fontWeight(.medium)
                Text("Absolutely no personal information is collected or stored.")
                    .bold()
                    .foregroundStyle(Color(red: 0.5, green: 0.75, blue: 1))
                Text("holzBar never connects to the network.")
                    .bold()
                    .foregroundStyle(Color(red: 0.5, green: 0.75, blue: 1))
            }
            .padding()
        }
        .font(.title3)
    }

    @ViewBuilder
    private var permissionsStack: some View {
        VStack {
            explanationBox
            ForEach(launchPermissions) { permission in
                permissionBox(permission)
            }
            ForEach(laterPermissions) { permission in
                laterPermissionBox(permission)
            }
        }
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        Button {
            appState.dismissWindow(.permissions)

            guard manager.permissionsState != .missing else {
                appState.performSetup(hasPermissions: false)
                return
            }

            appState.performSetup(hasPermissions: true)

            Task {
                appState.activate(for: .settings)
                appState.openWindow(.settings)
            }
        } label: {
            Text("Continue")
                .frame(maxWidth: .infinity)
        }
        .disabled(manager.permissionsState == .missing)
    }

    /// A permission that a feature asks for when it is first used: what it is for, and no
    /// request.
    @ViewBuilder
    private func laterPermissionBox(_ permission: Permission) -> some View {
        HolzBarSection {
            VStack(spacing: 8) {
                Text(permission.title)
                    .font(.title.weight(.medium))
                    .underline()

                Text(ScreenRecordingFeature.summary)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)

                Text("holzBar asks for it the first time you use one of these.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if permission.hasPermission {
                    Text("Permission Granted")
                        .foregroundStyle(.green)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func permissionBox(_ permission: Permission) -> some View {
        HolzBarSection {
            VStack(spacing: 12) {
                Text(permission.title)
                    .font(.title.weight(.medium))
                    .underline()

                VStack(spacing: 2) {
                    Text("holzBar needs this to:")
                        .font(.title3)
                        .bold()

                    VStack(alignment: .leading) {
                        ForEach(permission.details, id: \.self) { detail in
                            HStack {
                                Text("•").bold()
                                Text(detail).fontWeight(.medium)
                            }
                        }
                    }
                }

                Button {
                    permission.performRequest()
                    Task {
                        guard await permission.waitForPermission() else {
                            return
                        }
                        appState.activate(for: .permissions)
                        appState.openWindow(.permissions)
                    }
                } label: {
                    if permission.hasPermission {
                        Text("Permission Granted")
                            .foregroundStyle(.green)
                    } else {
                        Text("Grant Permission")
                    }
                }
                .allowsHitTesting(!permission.hasPermission)

                if !permission.hasPermission && permission.canReset {
                    VStack(spacing: 2) {
                        Text("Already granted in System Settings?")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Reset and Grant Again") {
                            permission.resetAndRequest()
                            Task {
                                guard await permission.waitForPermission() else {
                                    return
                                }
                                appState.activate(for: .permissions)
                                appState.openWindow(.permissions)
                            }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }
}
