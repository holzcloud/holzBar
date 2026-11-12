//
//  HotkeysSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The hotkeys, grouped by goal: showing items, finding items, single items, profiles, modes and
/// modules. A hotkey whose feature is off stays visible, dimmed.
struct HotkeysSettingsPane: View {
    @Environment(AppState.self) var appState
    var settings: HotkeysSettings

    /// The names of the saved layout profiles.
    private var profileNames: [String] {
        appState.profiles.profiles.map(\.name)
    }

    /// A hotkey that opens a menu bar item, with the item's identity key.
    private struct ItemHotkey: Identifiable {
        let key: String
        let hotkey: Hotkey

        var id: String { key }
    }

    /// The hotkeys that open a menu bar item.
    private var itemHotkeys: [ItemHotkey] {
        settings.dynamicHotkeys.compactMap { hotkey in
            guard case .openItem(let key) = hotkey.target, hotkey.keyCombination != nil else {
                return nil
            }
            return ItemHotkey(key: key, hotkey: hotkey)
        }
    }

    var body: some View {
        SettingsPaneHost(.hotkeys) {
            SettingsGroup(SettingsCatalog.HotkeysPane.showItems) {
                if isSectionEnabled(.hidden) {
                    hotkeyRow(.hotkeysToggleHidden, action: .toggleHiddenSection)
                }
                hotkeyRow(.hotkeysToggleAlwaysHidden, action: .toggleAlwaysHiddenSection, small: Text("needs Always Hidden"))
                    .settingsDependent(on: isSectionEnabled(.alwaysHidden))
                hotkeyRow(.hotkeysShowForAMoment, action: .showHiddenSectionTemporarily)
            }
            SettingsGroup(SettingsCatalog.HotkeysPane.findItems) {
                hotkeyRow(.hotkeysSearch, action: .searchMenuBarItems)
                hotkeyRow(.hotkeysItemHints, action: .showItemHints)
                hotkeyRow(.hotkeysCommandPalette, action: .openCommandPalette)
            }
            SettingsGroup(
                SettingsCatalog.HotkeysPane.singleItems,
                footnote: Text("Give an item its own hotkey in Layout, with Set Hotkey… in the item's menu.")
            ) {
                itemHotkeyRows
            }
            SettingsGroup(
                SettingsCatalog.HotkeysPane.profiles,
                footnote: Text("Every profile saved in Profiles & History gets a row here.")
            ) {
                profileHotkeyRows
            }
            SettingsGroup(SettingsCatalog.HotkeysPane.modes) {
                hotkeyRow(.hotkeysShelf, action: .enableShelf)
                hotkeyRow(.hotkeysAutoRehide, action: .toggleAutoRehide)
                hotkeyRow(.hotkeysZenMode, action: .toggleZenMode)
                hotkeyRow(.hotkeysKeepAwake, action: .toggleKeepAwake)
                hotkeyRow(.hotkeysAppMenus, action: .toggleApplicationMenus, badge: appMenusBadge)
            }
            SettingsGroup(
                SettingsCatalog.HotkeysPane.modules,
                footnote: Text("Module hotkeys are set here only, not in Modules.")
            ) {
                hotkeyRow(.hotkeysNotchHub, action: .toggleNotchHub, small: Text("needs Notch hub"))
                    .settingsDependent(on: appState.modules.isEnabled(NotchHubController.moduleID))
            }
        }
        .task(id: profileNames) {
            // Each profile gets its hotkey object here, outside the view update, so the
            // rows only read them.
            for name in profileNames {
                _ = settings.hotkey(for: .applyProfile(name))
            }
        }
    }

    /// The app-menus hotkey works on macOS 27 too, which nobody has tested yet (D-59).
    private var appMenusBadge: SettingsBadge? {
        if #available(macOS 27.0, *) {
            return .preview
        }
        return nil
    }

    private func isSectionEnabled(_ name: MenuBarSection.Name) -> Bool {
        appState.menuBarManager.section(withName: name)?.isEnabled == true
    }

    @ViewBuilder
    private func hotkeyRow(
        _ entry: SettingsEntry,
        action: HotkeyAction,
        small: Text? = nil,
        badge: SettingsBadge? = nil
    ) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            SettingsHotkeyRow(entry, hotkey: hotkey, settings: settings, small: small, badge: badge)
        }
    }

    @ViewBuilder
    private var profileHotkeyRows: some View {
        if profileNames.isEmpty {
            SettingsStateLine(.info, Text("No profile is saved yet."))
        } else {
            ForEach(profileNames, id: \.self) { name in
                if let hotkey = settings.existingHotkey(for: .applyProfile(name)) {
                    SettingsHotkeyRow(Text(verbatim: name), hotkey: hotkey, settings: settings)
                }
            }
        }
    }

    @ViewBuilder
    private var itemHotkeyRows: some View {
        if itemHotkeys.isEmpty {
            SettingsStateLine(.info, Text("No item has its own hotkey yet."))
        } else {
            ForEach(itemHotkeys) { entry in
                SettingsRow(Text(verbatim: settings.name(of: entry.hotkey.target))) {
                    HotkeyRecorder(hotkey: entry.hotkey, settings: settings) {
                        Text(verbatim: settings.name(of: entry.hotkey.target))
                    }
                    .labelsHidden()
                    Button {
                        settings.removeHotkey(for: .openItem(entry.key))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove the hotkey of this item")
                    .accessibilityLabel("Remove")
                }
            }
        }
    }
}
