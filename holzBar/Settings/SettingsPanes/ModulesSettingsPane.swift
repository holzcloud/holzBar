//
//  ModulesSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The pane that lists the optional modules in two groups, Menu Bar and Notch.
///
/// Every module is off until the user switches it on. A module's settings open with its row's
/// chevron, one module at a time, and every module is closed again when the pane is left. The
/// switches write the module store, which is what the modules themselves read, so an off module
/// runs nothing.
struct ModulesSettingsPane: View {
    @Environment(AppState.self) private var appState

    /// The modules this Mac can run.
    private var modules: [ModuleDescriptor] {
        ModuleCatalog.all.filter { SettingsCatalog.ModulesPane.isSupported($0) }
    }

    private var openModule: Binding<String?> {
        Binding(
            get: { appState.navigationState.settingsSearch.openModule },
            set: { appState.navigationState.settingsSearch.openModule = $0 }
        )
    }

    var body: some View {
        SettingsPaneHost(.modules) {
            SettingsGroup(SettingsCatalog.ModulesPane.menuBar) {
                moduleList(in: .menuBar)
            }
            SettingsGroup(
                SettingsCatalog.ModulesPane.notch,
                footnote: Text("Hub modules work only while the Notch hub is on.")
            ) {
                moduleList(in: .notch)
            }
        }
        .onDisappear {
            // Leaving the pane closes the open module; a jump to a module sets it again.
            appState.navigationState.settingsSearch.openModule = nil
        }
    }

    private func moduleList(in area: ModuleArea) -> some View {
        ModuleListView(
            modules: ModuleCatalog.modules(in: area, of: modules),
            store: appState.modules,
            openModule: openModule,
            entry: { SettingsCatalog.ModulesPane.moduleEntry(for: $0) },
            small: { smallText(for: $0) },
            parent: { parentID(of: $0) },
            hasSettings: { hasSettings($0) },
            settings: { module in
                settings(of: module)
            }
        )
    }

    /// The small text of a module's row: what it needs or asks for. The switch has no default:
    /// a new case of ``ModulePermission`` must be placed here.
    private func smallText(for module: ModuleDescriptor) -> Text? {
        switch module.id {
        case MenuBarDragController.moduleID:
            return Text("from macOS 26 · needs Accessibility")
        case AppleItems.moduleID:
            return Text("macOS 27 only")
        case "live-activities":
            return Text("Downloads: folder access")
        default:
            break
        }
        guard let permission = module.permission else {
            return nil
        }
        switch permission {
        case .calendar: return Text("asks for Calendar access")
        case .bluetooth: return Text("needs Bluetooth")
        case .accessibility: return Text("needs Accessibility")
        case .screenRecording, .inputMonitoring, .microphone, .camera, .notifications,
            .fullDiskAccess, .files:
            return nil
        }
    }

    /// The module whose switch this module depends on: every hub module depends on the Notch
    /// hub.
    private func parentID(of module: ModuleDescriptor) -> String? {
        HubModules.registration(for: module.id) != nil ? NotchHubController.moduleID : nil
    }

    /// Whether the module's row has settings to open. Drag in the Menu Bar has a note only on
    /// macOS 27.
    private func hasSettings(_ module: ModuleDescriptor) -> Bool {
        if module.id == MenuBarDragController.moduleID {
            if #available(macOS 27.0, *) {
                return true
            }
            return false
        }
        return true
    }

    @ViewBuilder
    private func settings(of module: ModuleDescriptor) -> some View {
        if module.id == MenuBarWidgets.moduleID {
            WidgetsSection(widgets: appState.widgets)
        } else if module.id == MenuBarDragController.moduleID {
            if #available(macOS 27.0, *) {
                SettingsNoteLine(Text("Drop an item on the holzBar icon or on the open Shelf to hide its app."))
            }
        } else if module.id == AppleItems.moduleID {
            AppleItemsSection(appleItems: appState.appleItems)
        } else if module.id == NotchHubController.moduleID {
            NotchHubSettingsView(settings: appState.settings.notchHub)
        } else if let registration = HubModules.registration(for: module.id) {
            // A module of the Notch hub brings its own settings.
            registration.makeSettings()
        }
    }
}
