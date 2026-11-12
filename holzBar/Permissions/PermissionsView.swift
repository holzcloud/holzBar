//
//  PermissionsView.swift
//  holzBar
//

import SwiftUI

/// The first-launch window: only what the menu bar manager needs, Accessibility (required)
/// and Screen Recording (optional), on the rows of Advanced (D-24).
struct PermissionsView: View {
    @Environment(AppState.self) var appState
    @Environment(AppPermissions.self) var manager
    @State private var revoking: Permission?

    /// The window's width.
    private static let width: CGFloat = 550

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical, HolzBarTheme.Spacing.md)

            permissionsList

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .frame(width: Self.width)
        .fixedSize()
        .permissionRevokeConfirmation($revoking)
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
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
            }
            Spacer(minLength: 0)
        }
    }

    /// The two permissions of the menu bar manager and where the others are asked.
    private var permissionsList: some View {
        SettingsGroup {
            PermissionRow(
                manager.accessibility,
                entry: .advancedPermissionAccessibility,
                small: Text("required"),
                onGrant: { request($0) },
                onRevoke: { revoking = $0 },
                showsReset: true,
                onReset: { request($0, reset: true) }
            )
            PermissionRow(
                manager.screenRecording,
                entry: .advancedPermissionScreenRecording,
                small: Text("optional"),
                onGrant: { request($0) },
                onRevoke: { revoking = $0 },
                showsReset: true,
                onReset: { request($0, reset: true) }
            )
            SettingsNoteLine(Text("Calendar and Bluetooth are asked when you switch on the module that needs them."))
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

            // While the onboarding waits, it comes instead of Settings (D-20).
            guard OnboardingPolicy.continueOpensSettings(
                isPending: Defaults.bool(forKey: .onboardingPending),
                hasImportedSettings: appState.didImportPreviousSettings
            ) else {
                return
            }
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
}
