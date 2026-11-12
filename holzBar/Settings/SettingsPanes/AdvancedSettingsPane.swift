//
//  AdvancedSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The rare settings: the menu bar's own behaviour, app menus, backing up settings and the
/// permissions holzBar has or needs, on the settings kit.
struct AdvancedSettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var settings: AdvancedSettings
    @State private var revokingPermission: Permission?

    var body: some View {
        SettingsPaneHost(.advanced) {
            // Settings that do nothing on macOS 27 are not shown there (jordanbaird/Ice#1001);
            // their stored values are kept.
            SettingsGroup(SettingsCatalog.AdvancedPane.menuBar) {
                if !isMacOS27 {
                    SettingsPickerRow(
                        .advancedDividerStyle,
                        selection: $settings.sectionDividerStyle,
                        small: Text("macOS 14 to 26")
                    ) {
                        ForEach(SectionDividerStyle.allCases) { style in
                            Text(style.localized).tag(style)
                        }
                    }
                    SettingsToggleRow(
                        .advancedShowAllSectionsOnDrag,
                        isOn: $settings.showAllSectionsOnUserDrag,
                        small: Text("macOS 14 to 26")
                    )
                }
                SettingsToggleRow(.advancedSecondaryContextMenu, isOn: $settings.enableSecondaryContextMenu)
                if !isMacOS27 {
                    SettingsToggleRow(
                        .advancedKeepLiveActivities,
                        isOn: $settings.keepLiveActivitiesVisible,
                        small: Text("macOS 14 to 26"),
                        badge: .beta
                    )
                    SettingsToggleRow(
                        .advancedSystemItemsInPlace,
                        isOn: Binding(
                            get: { !Defaults.bool(forKey: .systemItemsMayHide) },
                            set: { Defaults.set(!$0, forKey: .systemItemsMayHide) }
                        ),
                        small: Text("macOS 14 to 26")
                    )
                }
            }
            if !isMacOS27 {
                SettingsGroup(SettingsCatalog.AdvancedPane.appMenus) {
                    SettingsToggleRow(
                        .advancedHideAppMenus,
                        isOn: $settings.hideApplicationMenus,
                        small: Text("macOS 14 to 26")
                    )
                    SettingsToggleRow(
                        .advancedKeepDockIconHidden,
                        isOn: $settings.keepsDockIconHidden,
                        small: Text("macOS 14 to 26")
                    )
                    .settingsSubRow()
                    .settingsDependent(on: settings.hideApplicationMenus)
                }
            }
            SettingsGroup(SettingsCatalog.AdvancedPane.backUp) {
                SettingsButtonRow(.advancedExportSettings) {
                    Button("Export…") {
                        SettingsBackup.exportToFile(attachedTo: appState.navigationState.settingsWindow)
                    }
                }
                SettingsButtonRow(.advancedImportSettings) {
                    Button("Import…") {
                        SettingsBackup.importFromFile(attachedTo: appState.navigationState.settingsWindow)
                    }
                }
            }
            SettingsGroup(SettingsCatalog.AdvancedPane.permissions) {
                ForEach(listedPermissions, id: \.self) { kind in
                    if let permission = appState.permissions.permission(for: kind), let entry = entry(for: kind) {
                        permissionRow(permission, entry: entry)
                    }
                }
            }
        }
        .onAppear {
            appState.permissions.refresh()
        }
        .sheet(item: $revokingPermission) { permission in
            ConfirmSheet(
                title: Text("Revoke this permission?"),
                message: Text("holzBar stops using it at once and cannot do what needs it until you allow it again. You can also remove it yourself in System Settings, in Privacy & Security."),
                confirmTitle: "Revoke \(permission.title)",
                cancelTitle: "Cancel",
                isDestructive: true,
                secondaryTitle: "Open System Settings",
                onSecondary: {
                    revokingPermission = nil
                    permission.openSettings()
                },
                onConfirm: {
                    revokingPermission = nil
                    permission.revoke()
                },
                onCancel: {
                    revokingPermission = nil
                }
            )
        }
    }

    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            true
        } else {
            false
        }
    }

    // MARK: Permissions

    /// The permissions a switched-on module needs, the granted ones and Accessibility (D-57,
    /// D-65), in their fixed order.
    private var listedPermissions: [ModulePermission] {
        let enabled = Set(ModuleCatalog.all.map(\.id).filter { appState.modules.isEnabled($0) })
        let needed = PermissionListing.needs(ofEnabled: enabled, in: ModuleCatalog.all)
        let granted = Set(PermissionListing.candidates.filter {
            appState.permissions.permission(for: $0)?.hasPermission == true
        })
        return PermissionListing.listed(needed: needed, granted: granted)
    }

    /// The catalog entry of a listed permission. The switch has no default: a new candidate
    /// needs its entry here.
    private func entry(for kind: ModulePermission) -> SettingsEntry? {
        switch kind {
        case .accessibility: .advancedPermissionAccessibility
        case .screenRecording: .advancedPermissionScreenRecording
        case .calendar: .advancedPermissionCalendar
        case .bluetooth: .advancedPermissionBluetooth
        case .inputMonitoring, .microphone, .camera, .notifications, .fullDiskAccess, .files: nil
        }
    }

    /// One permission: its state and the one button that fits it. "Grant…" asks only on this
    /// click; "Revoke…" asks first.
    private func permissionRow(_ permission: Permission, entry: SettingsEntry) -> some View {
        SettingsRow(entry) {
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
                            revokingPermission = permission
                        }
                    }
                } else {
                    Button("Grant…") {
                        permission.performRequest()
                    }
                }
            }
        }
    }
}
