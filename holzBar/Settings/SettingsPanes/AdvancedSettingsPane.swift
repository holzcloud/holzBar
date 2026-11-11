//
//  AdvancedSettingsPane.swift
//  holzBar
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var settings: AdvancedSettings
    @State private var revokingPermission: Permission?

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    var body: some View {
        HolzBarForm {
            // Settings that do nothing on macOS 27 are not shown there (jordanbaird/Ice#1001):
            // there are no dividers to style, no drags on the bar, no item moves and no
            // hiding of application menus. Their stored values are kept.
            HolzBarSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                if !isMacOS27 {
                    showAllSectionsOnUserDrag
                    sectionDividerStyle
                }
                newItemsPlacement
                if !isMacOS27 {
                    keepLiveActivitiesVisible
                }
            }
            HolzBarSection("Other") {
                if !isMacOS27 {
                    hideApplicationMenus
                    keepsDockIconHidden
                }
                enableSecondaryContextMenu
                if !isMacOS27 {
                    pinSystemItems
                }
            }
            HolzBarSection("Settings") {
                settingsBackup
            }
            HolzBarSection("Permissions") {
                allPermissions
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

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable the always-hidden section",
            isOn: $settings.enableAlwaysHiddenSection
        )
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $settings.showAllSectionsOnUserDrag
        )
    }

    @ViewBuilder
    private var newItemsPlacement: some View {
        HolzBarPicker("Place new menu bar items in", selection: $settings.newItemsPlacement) {
            ForEach(NewItemsPlacement.allCases) { placement in
                if placement != .alwaysHidden || settings.enableAlwaysHiddenSection {
                    Text(placement.localized).tag(placement)
                }
            }
        }
        .annotation("Applies to items holzBar has not seen before. Items that are already arranged stay where they are.")
    }

    @ViewBuilder
    private var keepLiveActivitiesVisible: some View {
        Toggle("Keep Live Activities visible", isOn: $settings.keepLiveActivitiesVisible)
            .annotation("Live Activities from your iPhone stay in the menu bar instead of being hidden. Experimental.")
    }

    @ViewBuilder
    private var sectionDividerStyle: some View {
        HolzBarPicker("Section divider style", selection: $settings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(
            "Hide app menus when showing menu bar items",
            isOn: $settings.hideApplicationMenus
        )
        .annotation {
            if #available(macOS 27.0, *) {
                Text("Not needed on macOS 27, which folds items that do not fit behind its own overflow button.")
                    .padding(.trailing, 75)
            } else {
                Text(
                    """
                    Make more room in the menu bar by hiding the current app menus if \
                    needed. macOS requires holzBar to make itself visible in the Dock while \
                    this setting is in effect.
                    """
                )
                .padding(.trailing, 75)
            }
        }
        .disabled(isMacOS27)
    }

    @ViewBuilder
    private var keepsDockIconHidden: some View {
        Toggle("Keep the Dock icon hidden", isOn: $settings.keepsDockIconHidden)
            .annotation {
                Text(
                    """
                    macOS hides another app's menus only while holzBar is in the Dock. With \
                    this on, holzBar never shows a Dock icon, and the menus stay.
                    """
                )
                .padding(.trailing, 75)
            }
            .disabled(isMacOS27 || !settings.hideApplicationMenus)
    }

    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            true
        } else {
            false
        }
    }

    @ViewBuilder
    private var enableSecondaryContextMenu: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: $settings.enableSecondaryContextMenu
        )
        .annotation {
            Text(
                """
                Right-click in an empty area of the menu bar to display a minimal \
                version of holzBar's menu. Disable this setting if you encounter conflicts \
                with other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var pinSystemItems: some View {
        Toggle(
            isOn: Binding(
                get: { !Defaults.bool(forKey: .systemItemsMayHide) },
                set: { Defaults.set(!$0, forKey: .systemItemsMayHide) }
            )
        ) {
            Text("Keep the clock, battery, Wi-Fi, Control Center and sound visible")
        }
        .annotation("Profiles, restored layouts and rules leave these items where they are. You can still move them yourself.")
    }

    @ViewBuilder
    private var settingsBackup: some View {
        LabeledContent {
            HStack {
                Button("Export…") {
                    SettingsBackup.exportToFile(attachedTo: appState.navigationState.settingsWindow)
                }
                Button("Import…") {
                    SettingsBackup.importFromFile(attachedTo: appState.navigationState.settingsWindow)
                }
            }
        } label: {
            Text("Back up or move your settings")
        }
        .annotation("Exports layout, hotkeys and appearance to a file that can be imported on another Mac.")
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissions.allPermissions) { permission in
            LabeledContent {
                if permission.hasPermission {
                    HStack {
                        PermissionPill(Text("Permission Granted"), state: .granted)
                        if permission.canReset {
                            Button("Revoke…") {
                                revokingPermission = permission
                            }
                        }
                    }
                } else {
                    HStack {
                        PermissionPill(Text("Needs \(permission.title)"), state: .needed)
                        Button("Grant Permission") {
                            permission.performRequest()
                        }
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}
