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

    /// The modules this Mac can run: Drag in the Menu Bar is left out where it is unsupported.
    private var modules: [ModuleDescriptor] {
        ModuleCatalog.all.filter { module in
            module.id != MenuBarDragController.moduleID || MenuBarDragController.isSupported
        }
    }

    var body: some View {
        ModuleListView(
            modules: modules,
            store: appState.modules,
            areaTitle: areaTitle(for:),
            title: { Text(LocalizedStringKey($0.titleKey)) },
            summary: { Text(LocalizedStringKey($0.summaryKey)) },
            permissionText: { Text(verbatim: $0.rawValue) },
            isPermissionGranted: { _ in false },
            emptyTitle: Text("No modules"),
            emptyMessage: Text("Modules you can switch on appear here.")
        ) { module in
            settings(of: module)
        }
    }

    /// The title above the group of an area. A module of another area needs its title here;
    /// the test of the module catalog fails until it has one.
    private func areaTitle(for area: ModuleArea) -> Text {
        switch area {
        case .menuBar: Text("Menu Bar")
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
        }
    }
}
