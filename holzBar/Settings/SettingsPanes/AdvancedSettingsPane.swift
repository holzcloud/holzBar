//
//  AdvancedSettingsPane.swift
//  holzBar
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            "\(formatted) second"
        } else {
            "\(formatted) seconds"
        }
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
                showOnHoverDelay
                tempShowInterval
                openHiddenItemsInMenuBar
                autoZenWhileSharingScreen
            }
            HolzBarSection("Show Hidden Items Automatically") {
                RevealRulesSettings(rules: appState.revealRules)
            }
            HolzBarSection("Settings") {
                settingsBackup
                settingsSync
            }
            HolzBarSection("Permissions") {
                allPermissions
            }
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
    private var showOnHoverDelay: some View {
        LabeledContent {
            HolzBarSlider(
                formattedToSeconds(settings.showOnHoverDelay),
                value: $settings.showOnHoverDelay,
                in: 0...1,
                step: 0.1
            )
        } label: {
            Text("Show on hover delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing on hover.")
    }

    @ViewBuilder
    private var tempShowInterval: some View {
        LabeledContent {
            HolzBarSlider(
                formattedToSeconds(settings.tempShowInterval),
                value: $settings.tempShowInterval,
                in: 0...30,
                step: 1
            )
        } label: {
            Text("Hide opened items again after")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("Counted from when the item's menu closes. 0 hides it right away.")
    }

    @ViewBuilder
    private var openHiddenItemsInMenuBar: some View {
        Toggle("Open hidden items in the menu bar", isOn: $settings.openHiddenItemsInMenuBar)
            .annotation("Shows a hidden item in the menu bar and opens its menu under it. Off, the menu opens without showing the item.")
    }

    @ViewBuilder
    private var autoZenWhileSharingScreen: some View {
        Toggle("Turn on Zen mode while the screen is mirrored or shared", isOn: $settings.autoZenWhileSharingScreen)
            .annotation("Uses no permission: holzBar notices a mirrored display and macOS's screen sharing agent.")
    }

    @ViewBuilder
    private var settingsBackup: some View {
        LabeledContent {
            HStack {
                Button("Export…") {
                    SettingsBackup.exportToFile()
                }
                Button("Import…") {
                    SettingsBackup.importFromFile()
                }
            }
        } label: {
            Text("Back up or move your settings")
        }
        .annotation("Exports layout, hotkeys and appearance to a file that can be imported on another Mac.")
    }

    @ViewBuilder
    private var settingsSync: some View {
        SettingsSyncToggle(sync: appState.settingsSync)
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissions.allPermissions) { permission in
            LabeledContent {
                if permission.hasPermission {
                    Label {
                        Text("Permission Granted")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Grant Permission") {
                        permission.performRequest()
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}

// MARK: - RevealRulesSettings

/// Settings for showing hidden items when something needs attention
/// (jordanbaird/Ice#62).
private struct RevealRulesSettings: View {
    @Bindable var rules: RevealRules

    var body: some View {
        Toggle("When the battery is low", isOn: $rules.revealsOnLowBattery)
        if rules.revealsOnLowBattery {
            Stepper(value: $rules.lowBatteryThreshold, in: 5...50, step: 5) {
                Text("Below \((Double(rules.lowBatteryThreshold) / 100).formatted(.percent))")
            }
        }
        Toggle("When the network connection is lost", isOn: $rules.revealsWhenOffline)
            .annotation("Hidden items are shown for the time set in \u{201C}Hide opened items again after\u{201D}, then hidden again.")
    }
}

// MARK: - SettingsSyncToggle

/// Turns syncing the settings on or off, through iCloud Drive or any folder the Macs keep
/// in sync (jordanbaird/Ice#95, SYNC-01).
private struct SettingsSyncToggle: View {
    @Bindable var sync: SettingsSync

    var body: some View {
        LabeledContent {
            HStack {
                if sync.isEnabled {
                    Button("Change…") {
                        sync.chooseFolder()
                    }
                    Button("Turn Off") {
                        sync.isEnabled = false
                    }
                } else {
                    Button("Turn On…") {
                        sync.chooseFolder()
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync settings between your Macs")
                if sync.isEnabled {
                    if let folder = sync.folderDisplayName {
                        Text("Through \(folder)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("The sync folder cannot be found. Choose it again.")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .annotation(
            "Keeps layout, profiles, hotkeys and appearance the same on all your Macs through a folder they sync: iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing or a network share. The folder's own app carries the file; holzBar never goes online. Changes from another Mac apply after a restart."
        )
    }
}
