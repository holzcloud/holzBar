//
//  PermissionRow.swift
//  holzBar
//

import SwiftUI

/// One permission on a settings-kit row: its state and the one button that fits it. The
/// first-launch window and Advanced share it, so they cannot drift (D-24). "Grant…" asks only
/// on this click; "Revoke…" asks first.
struct PermissionRow: View {
    private let permission: Permission
    private let entry: SettingsEntry
    private let small: Text?
    private let onGrant: (Permission) -> Void
    private let onRevoke: (Permission) -> Void
    private let showsReset: Bool
    private let onReset: ((Permission) -> Void)?

    init(
        _ permission: Permission,
        entry: SettingsEntry,
        small: Text? = nil,
        onGrant: @escaping (Permission) -> Void,
        onRevoke: @escaping (Permission) -> Void,
        showsReset: Bool = false,
        onReset: ((Permission) -> Void)? = nil
    ) {
        self.permission = permission
        self.entry = entry
        self.small = small
        self.onGrant = onGrant
        self.onRevoke = onRevoke
        self.showsReset = showsReset
        self.onReset = onReset
    }

    var body: some View {
        SettingsRow(entry, small: small) {
            HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                Group {
                    if permission.hasPermission {
                        Text("Granted")
                    } else {
                        Text("Not granted")
                    }
                }
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                if permission.hasPermission {
                    if permission.canReset {
                        Button("Revoke…") {
                            onRevoke(permission)
                        }
                    }
                } else {
                    Button("Grant…") {
                        onGrant(permission)
                    }
                }
            }
        }
        if showsReset, !permission.hasPermission, permission.canReset {
            // A permission macOS lists as granted but holzBar cannot use: the fix of
            // Ice #1004 and #834.
            SettingsButtonRow(Text("Already granted in System Settings?")) {
                Button("Reset and Grant Again") {
                    onReset?(permission)
                }
            }
            .settingsSubRow()
        }
    }
}

extension View {
    /// Asks before a permission is revoked, with System Settings as the other way.
    func permissionRevokeConfirmation(_ permission: Binding<Permission?>) -> some View {
        sheet(item: permission) { revoking in
            ConfirmSheet(
                title: Text("Revoke this permission?"),
                message: Text("holzBar stops using it at once and cannot do what needs it until you allow it again. You can also remove it yourself in System Settings, in Privacy & Security."),
                confirmTitle: "Revoke \(revoking.title)",
                cancelTitle: "Cancel",
                isDestructive: true,
                secondaryTitle: "Open System Settings",
                onSecondary: {
                    permission.wrappedValue = nil
                    revoking.openSettings()
                },
                onConfirm: {
                    permission.wrappedValue = nil
                    revoking.revoke()
                },
                onCancel: {
                    permission.wrappedValue = nil
                }
            )
        }
    }
}
