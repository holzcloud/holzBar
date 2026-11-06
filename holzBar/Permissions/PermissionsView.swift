//
//  PermissionsView.swift
//  holzBar
//

import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) var appState
    @Environment(AppPermissions.self) var manager

    /// The window's width.
    private static let width: CGFloat = 550

    /// The most the permission rows take: a window is never taller than four fifths of the
    /// screen, so Quit and Continue stay on it; the rows scroll when they do not fit.
    private var maximumRowsHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 700
        return max(240, screenHeight * 0.8 - 190)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical, HolzBarTheme.Spacing.md)

            ScrollView {
                permissionsList
                    .padding(.bottom, HolzBarTheme.Spacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maximumRowsHeight)
            .fixedSize(horizontal: false, vertical: true)

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .frame(width: Self.width)
        .fixedSize()
        .onDisappear {
            appState.hideDockIconIfUnneeded()
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: HolzBarTheme.Spacing.md) {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    // Decorative: the title says what the window is.
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text("Permissions")
                    .font(HolzBarTheme.Typography.titleLarge)
                    .accessibilityAddTraits(.isHeader)
                Text("holzBar never connects to the network.")
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .fontWeight(.medium)
            }
            Spacer(minLength: 0)
        }
    }

    /// One row per permission: the name and what it is for on the left, its state or its
    /// button on the right.
    @ViewBuilder
    private var permissionsList: some View {
        HolzBarSection {
            ForEach(manager.allPermissions) { permission in
                permissionRow(permission)
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
        // The window's default button: Return continues once the permissions are granted.
        .keyboardShortcut(.defaultAction)
        .disabled(manager.permissionsState == .missing)
    }

    /// Asks for a permission, then brings this window back once macOS has granted it.
    private func request(_ permission: Permission, reset: Bool = false) {
        if reset {
            permission.resetAndRequest()
        } else {
            permission.performRequest()
        }
        Task {
            guard await permission.waitForPermission() else {
                return
            }
            appState.activate(for: .permissions)
            appState.openWindow(.permissions)
        }
    }

    @ViewBuilder
    private func permissionRow(_ permission: Permission) -> some View {
        HStack(alignment: .center, spacing: HolzBarTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text(permission.title)
                    .font(HolzBarTheme.Typography.headline)
                if let summary = permission.summary {
                    Text(verbatim: summary)
                        .font(.callout)
                }
                if let withoutNote = permission.withoutNote {
                    Text(verbatim: withoutNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // A permission asked for at launch lists what holzBar does with it instead.
                ForEach(permission.summary == nil ? permission.details : [], id: \.self) { detail in
                    Text(verbatim: detail)
                        .font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            permissionControl(permission)
        }
        .padding(.vertical, HolzBarTheme.Spacing.sm)
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    /// The state of a permission, or the button that asks for it.
    @ViewBuilder
    private func permissionControl(_ permission: Permission) -> some View {
        VStack(alignment: .trailing, spacing: HolzBarTheme.Spacing.xs) {
            if permission.hasPermission {
                PermissionPill(Text("Permission Granted"), state: .granted)
                if permission.summary != nil, permission.canReset {
                    Button("Revoke Permission") {
                        permission.revoke()
                    }
                    .controlSize(.small)
                }
            } else {
                Button("Grant Permission") {
                    request(permission)
                }
                if permission.canReset {
                    Button("Reset and Grant Again") {
                        request(permission, reset: true)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help(Text("Already granted in System Settings?"))
                }
            }
        }
    }
}
