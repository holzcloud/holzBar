//
//  ModulesSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The pane that lists the optional modules, one glass group per area.
///
/// Every module is off until the user switches it on, and a module's settings open under its
/// row only while it is on. The switches write the module store, which is what the modules
/// themselves read, so an off module runs nothing.
struct ModulesSettingsPane: View {
    @Environment(AppState.self) private var appState

    /// The modules this Mac can run: Drag in the Menu Bar and Apple Items are left out where
    /// they are unsupported.
    private var modules: [ModuleDescriptor] {
        ModuleCatalog.all.filter { module in
            switch module.id {
            case MenuBarDragController.moduleID: MenuBarDragController.isSupported
            case AppleItems.moduleID: AppleItems.isSupported
            default: true
            }
        }
    }

    var body: some View {
        ModuleListView(
            modules: modules,
            store: appState.modules,
            areaTitle: areaTitle(for:),
            title: { Text(LocalizedStringKey($0.titleKey)) },
            summary: { Text(LocalizedStringKey($0.summaryKey)) },
            permissionText: permissionText(_:),
            isPermissionGranted: isGranted(_:),
            emptyTitle: Text("No modules"),
            emptyMessage: Text("Modules you can switch on appear here."),
            settings: { module in
                settings(of: module)
            }
        )
    }

    /// The quiet line under a module that asks for a permission: what it asks and when. The
    /// switch has no default: a new case of ``ModulePermission`` must be placed here.
    private func permissionText(_ permission: ModulePermission) -> Text {
        switch permission {
        case .calendar: Text("Asks for Calendar access when you switch it on")
        case .bluetooth: Text("Needs Bluetooth")
        case .accessibility, .screenRecording, .inputMonitoring, .microphone, .camera, .notifications,
            .fullDiskAccess, .files:
            Text(verbatim: permission.rawValue)
        }
    }

    /// Whether holzBar has the permission a module asks for. A permission holzBar has no
    /// lookup for yet is not granted. The switch has no default: a new case of
    /// ``ModulePermission`` must be placed here.
    private func isGranted(_ permission: ModulePermission) -> Bool {
        switch permission {
        case .accessibility: appState.permissions.accessibility.hasPermission
        case .screenRecording: appState.permissions.screenRecording.hasPermission
        case .calendar: appState.permissions.calendar.hasPermission
        case .bluetooth: BluetoothDeviceMonitor.access == .allowed
        case .inputMonitoring, .microphone, .camera, .notifications, .fullDiskAccess, .files:
            false
        }
    }

    /// The title above the group of an area. A module of another area needs its title here;
    /// the test of the module catalog fails until it has one.
    private func areaTitle(for area: ModuleArea) -> Text {
        switch area {
        case .menuBar: Text("Menu Bar")
        case .notch: Text("Notch")
        default: Text(verbatim: area.rawValue)
        }
    }

    @ViewBuilder
    private func settings(of module: ModuleDescriptor) -> some View {
        if module.id == MenuBarWidgets.moduleID {
            WidgetsSection(widgets: appState.widgets)
        } else if module.id == MenuBarDragController.moduleID {
            if #available(macOS 27.0, *) {
                Text("Drop an item on the holzBar icon to hide its app.")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
