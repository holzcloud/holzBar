//
//  ModulesCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Modules pane, in the order the pane shows them: one entry
    /// per module this Mac can run, then the fixed rows inside and beside the modules' open areas.
    enum ModulesPane {
        static let menuBar = String(localized: "Menu Bar")
        static let notch = String(localized: "Notch")

        /// The group of an area. A module of another area needs its group here and in the pane;
        /// the test of the module catalog fails until it has one.
        static func group(of area: ModuleArea) -> String {
            switch area {
            case .menuBar: menuBar
            case .notch: notch
            default: area.rawValue
            }
        }

        /// Whether this Mac can run the module: Drag in the Menu Bar and Apple Items are left out
        /// where they are unsupported. The pane and the search list the same modules.
        static func isSupported(_ module: ModuleDescriptor) -> Bool {
            switch module.id {
            case MenuBarDragController.moduleID: MenuBarDragController.isSupported
            case AppleItems.moduleID: AppleItems.isSupported
            default: true
            }
        }

        /// The entry of a module's row: its title, and its summary as the info.
        static func moduleEntry(for module: ModuleDescriptor) -> SettingsEntry {
            let summary = Bundle.main.localizedString(forKey: module.summaryKey, value: nil, table: nil)
            return SettingsEntry(
                id: "modules.\(module.id)",
                pane: .modules,
                group: group(of: module.area),
                label: Bundle.main.localizedString(forKey: module.titleKey, value: nil, table: nil),
                info: summary,
                summary: summary,
                module: module.id
            )
        }

        /// The fixed rows inside the module rows' open areas and beside them. The plans of the
        /// module settings append their entries here.
        static let rowEntries: [SettingsEntry] = []

        /// Whether a row entry belongs to a module this Mac can run.
        static func isAvailable(_ entry: SettingsEntry) -> Bool {
            guard
                let moduleID = entry.module,
                let module = ModuleCatalog.all.first(where: { $0.id == moduleID })
            else {
                return true
            }
            return isSupported(module)
        }

        static let entries: [SettingsEntry] =
            ModuleCatalog.all.filter { isSupported($0) }.map { moduleEntry(for: $0) }
            + rowEntries.filter { isAvailable($0) }
    }
}
