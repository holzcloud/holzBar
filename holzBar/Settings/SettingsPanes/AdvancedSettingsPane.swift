//
//  AdvancedSettingsPane.swift
//  holzBar
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        HolzBarForm {
            HolzBarSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                showAllSectionsOnUserDrag
                sectionDividerStyle
                newItemsPlacement
                keepLiveActivitiesVisible
            }
            HolzBarSection("Other") {
                hideApplicationMenus
                enableSecondaryContextMenu
                showOnHoverDelay
                tempShowInterval
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
        .annotation("Applies to items holzIce has not seen before. Items that are already arranged stay where they are.")
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
                    needed. macOS requires holzIce to make itself visible in the Dock while \
                    this setting is in effect.
                    """
                )
                .padding(.trailing, 75)
            }
        }
        .disabled(isMacOS27)
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
                version of holzIce's menu. Disable this setting if you encounter conflicts \
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
                in: 0...60,
                step: 1
            )
        } label: {
            Text("Temporarily shown item delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before hiding temporarily shown menu bar items.")
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
    @ObservedObject var rules: RevealRules

    var body: some View {
        Toggle("When the battery is low", isOn: $rules.revealsOnLowBattery)
        if rules.revealsOnLowBattery {
            Stepper(value: $rules.lowBatteryThreshold, in: 5...50, step: 5) {
                Text("Below \(rules.lowBatteryThreshold) %")
            }
        }
        Toggle("When the network connection is lost", isOn: $rules.revealsWhenOffline)
            .annotation("Hidden items are shown for the temporarily shown item delay, then hidden again.")
    }
}

// MARK: - SettingsSyncToggle

/// Turns syncing the settings through iCloud Drive on or off (jordanbaird/Ice#95).
private struct SettingsSyncToggle: View {
    @ObservedObject var sync: SettingsSync

    private var annotation: LocalizedStringKey {
        if SettingsSync.iCloudDriveURL == nil {
            "Turn on iCloud Drive in System Settings to sync holzIce's settings between your Macs."
        } else {
            "Keeps layout, profiles, hotkeys and appearance the same on all your Macs. Changes from another Mac apply after a restart."
        }
    }

    var body: some View {
        Toggle("Sync settings with iCloud Drive", isOn: $sync.isEnabled)
            .disabled(SettingsSync.iCloudDriveURL == nil)
            .annotation(annotation)
    }
}
