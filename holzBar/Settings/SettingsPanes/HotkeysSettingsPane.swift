//
//  HotkeysSettingsPane.swift
//  holzBar
//

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings

    var body: some View {
        HolzBarForm {
            HolzBarSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
                hotkeyRecorder(forAction: .showHiddenSectionTemporarily)
            }
            HolzBarSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            HolzBarSection("Other") {
                hotkeyRecorder(forAction: .enableShelf)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
                hotkeyRecorder(forAction: .toggleAutoRehide)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .enableShelf:
                    Text("Enable the holzIce Bar")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                case .showHiddenSectionTemporarily:
                    Text("Show the hidden section for a moment")
                case .toggleAutoRehide:
                    Text("Turn auto-rehide on or off")
                }
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
