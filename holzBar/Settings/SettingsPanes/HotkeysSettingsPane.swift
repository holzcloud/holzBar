//
//  HotkeysSettingsPane.swift
//  holzBar
//

import SwiftUI

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
        HolzBarForm {
            HolzBarSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
                hotkeyRecorder(forAction: .showHiddenSectionTemporarily)
            }
            HolzBarSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
                hotkeyRecorder(forAction: .showItemHints)
                itemHotkeyRows
            }
            HolzBarSection("Layout Profiles") {
                profileHotkeyRows
            }
            HolzBarSection("Other") {
                hotkeyRecorder(forAction: .enableShelf)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
                hotkeyRecorder(forAction: .toggleAutoRehide)
                hotkeyRecorder(forAction: .toggleZenMode)
            }
        }
        .task(id: profileNames) {
            // Each profile gets its hotkey object here, outside the view update, so the
            // rows below only read them.
            for name in profileNames {
                _ = settings.hotkey(for: .applyProfile(name))
            }
        }
    }

    @ViewBuilder
    private var profileHotkeyRows: some View {
        if profileNames.isEmpty {
            Text("Save a layout profile in the Menu Bar Layout pane to give it a hotkey.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(profileNames, id: \.self) { name in
                if let hotkey = settings.existingHotkey(for: .applyProfile(name)) {
                    HotkeyRecorder(hotkey: hotkey, settings: settings) {
                        Text(name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var itemHotkeyRows: some View {
        ForEach(itemHotkeys) { entry in
            HStack {
                HotkeyRecorder(hotkey: entry.hotkey, settings: settings) {
                    Text(settings.name(of: entry.hotkey.target))
                }
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
        if itemHotkeys.isEmpty {
            Text("Give a menu bar item its own hotkey with Set Hotkey… in its menu in the Menu Bar Layout pane.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey, settings: settings) {
                Text(action.title)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}
