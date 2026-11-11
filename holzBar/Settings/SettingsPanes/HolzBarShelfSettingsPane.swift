//
//  HolzBarShelfSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The holzBar Shelf pane of the Settings window.
struct HolzBarShelfSettingsPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var general = appState.settings.general
        let shelfIsOn = general.useShelf

        SettingsPaneHost(.shelf) {
            SettingsGroup {
                SettingsToggleRow(
                    .shelfUse,
                    isOn: $general.useShelf,
                    info: general.useShelf ? nil : Text("Off: hidden menu bar items appear in the menu bar itself. Turn it on to show them in a separate bar under the menu bar.")
                )
                SettingsPictureRow {
                    ShelfOverviewPicture(
                        isOn: general.useShelf,
                        style: general.shelfStyle,
                        layout: general.shelfLayout
                    )
                }
            }
            lookGroup(general: general)
                .settingsDependent(on: shelfIsOn)
            useOnGroup(general: general)
                .settingsDependent(on: shelfIsOn)
            moreOptionsGroup
                .settingsDependent(on: shelfIsOn)
        }
    }

    // MARK: Look

    @ViewBuilder
    private func lookGroup(general: GeneralSettings) -> some View {
        @Bindable var general = general
        SettingsGroup(SettingsCatalog.ShelfPane.look) {
            SettingsPictureCardRow(
                .shelfStyle,
                selection: $general.shelfStyle,
                values: HolzBarShelfStyle.allCases,
                info: styleInfo(general.shelfStyle),
                name: { Text($0.localized) },
                picture: { ShelfStylePicture(style: $0) }
            )
            SettingsPictureCardRow(
                .shelfLayout,
                selection: $general.shelfLayout,
                values: ShelfLayout.allCases,
                name: { Text($0.localized) },
                picture: { ShelfLayoutPicture(layout: $0) }
            )
        }
    }

    /// What the chosen style does.
    private func styleInfo(_ style: HolzBarShelfStyle) -> Text {
        switch style {
        case .attached:
            Text("The holzBar Shelf hangs directly under the menu bar.")
        case .floating:
            Text("The holzBar Shelf floats a little under the menu bar, as a bar of its own.")
        }
    }

    // MARK: Use on

    @ViewBuilder
    private func useOnGroup(general: GeneralSettings) -> some View {
        @Bindable var general = general
        SettingsGroup(SettingsCatalog.ShelfPane.useOn) {
            SettingsPickerRow(.shelfDisplays, selection: $general.shelfDisplays) {
                ForEach(HolzBarShelfDisplays.allCases) { displays in
                    Text(displays.localized).tag(displays)
                }
            }
            SettingsToggleRow(.shelfNotchOverflow, isOn: $general.showsNotchOverflowInShelf)
        }
    }

    // MARK: More options

    /// The pane's one disclosure. It depends on the Shelf switch like the rows, which dims its
    /// header and keeps its chevron usable; the options inside inherit the dependency.
    @ViewBuilder
    private var moreOptionsGroup: some View {
        @Bindable var general = appState.settings.general
        SettingsGroup {
            SettingsDisclosure(
                Text(SettingsCatalog.ShelfPane.moreOptions),
                id: SettingsCatalog.ShelfPane.moreOptionsID
            ) {
                SettingsPickerRow(
                    .shelfLocation,
                    selection: $general.shelfLocation,
                    info: locationInfo(general.shelfLocation)
                ) {
                    ForEach(HolzBarShelfLocation.allCases) { location in
                        Text(location.localized).tag(location)
                    }
                }
                SettingsToggleRow(.shelfFindsByTyping, isOn: $general.shelfFindsByTyping)
                SettingsPickerRow(
                    .shelfAlwaysHiddenFold,
                    selection: $general.shelfAlwaysHiddenFold,
                    small: Text("needs Always Hidden")
                ) {
                    Text("Folded each time").tag(ShelfAlwaysHiddenFold.foldedEachTime)
                    Text("As I left them").tag(ShelfAlwaysHiddenFold.remembered)
                }
                .settingsDependent(on: appState.settings.advanced.enableAlwaysHiddenSection)
                SettingsToggleRow(.shelfShowsClosedApps, isOn: $general.shelfShowsClosedApps)
                SettingsToggleRow(.shelfDragsTiles, isOn: $general.shelfDragsTiles)
            }
        }
    }

    /// What the chosen location does.
    private func locationInfo(_ location: HolzBarShelfLocation) -> Text {
        switch location {
        case .dynamic:
            Text("The holzBar Shelf opens under the pointer when it rests on an empty area of the menu bar, otherwise under the holzBar icon.")
        case .mousePointer:
            Text("The holzBar Shelf is centered under the mouse pointer.")
        case .holzBarIcon:
            Text("The holzBar Shelf is centered under the holzBar icon.")
        case .screenEdge:
            Text("The holzBar Shelf is at the right edge of the screen.")
        }
    }
}
