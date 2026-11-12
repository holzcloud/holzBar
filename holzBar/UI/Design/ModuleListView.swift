//
//  ModuleListView.swift
//  holzBar
//

import SwiftUI

/// The rows of a list of optional modules, as kit module rows.
///
/// The view knows no module by name: what a row says comes from the closures. One module's
/// settings are open at a time, through the `openModule` binding. A module that depends on
/// another one's switch is a sub row, dimmed while that switch is off.
struct ModuleListView<Settings: View>: View {
    private let modules: [ModuleDescriptor]
    private let store: ModuleStore
    @Binding private var openModule: String?
    private let entry: (ModuleDescriptor) -> SettingsEntry
    private let small: (ModuleDescriptor) -> Text?
    private let parent: (ModuleDescriptor) -> String?
    private let hasSettings: (ModuleDescriptor) -> Bool
    private let settings: (ModuleDescriptor) -> Settings

    init(
        modules: [ModuleDescriptor],
        store: ModuleStore,
        openModule: Binding<String?>,
        entry: @escaping (ModuleDescriptor) -> SettingsEntry,
        small: @escaping (ModuleDescriptor) -> Text?,
        parent: @escaping (ModuleDescriptor) -> String?,
        hasSettings: @escaping (ModuleDescriptor) -> Bool,
        @ViewBuilder settings: @escaping (ModuleDescriptor) -> Settings
    ) {
        self.modules = modules
        self.store = store
        _openModule = openModule
        self.entry = entry
        self.small = small
        self.parent = parent
        self.hasSettings = hasSettings
        self.settings = settings
    }

    var body: some View {
        ForEach(modules) { module in
            if let parentID = parent(module) {
                row(for: module)
                    .settingsSubRow()
                    .settingsDependent(on: store.isEnabled(parentID))
            } else {
                row(for: module)
            }
        }
    }

    @ViewBuilder
    private func row(for module: ModuleDescriptor) -> some View {
        let isOn = Binding(
            get: { store.isEnabled(module.id) },
            set: { store.setEnabled(module.id, $0) }
        )
        let badge: SettingsBadge? = module.isPreview ? .preview : nil
        if hasSettings(module) {
            SettingsModuleRow(
                entry(module),
                systemImage: module.symbol,
                isOn: isOn,
                isOpen: isOpenBinding(for: module),
                small: small(module),
                badge: badge
            ) {
                settings(module)
            }
        } else {
            SettingsModuleRow(
                entry(module),
                systemImage: module.symbol,
                isOn: isOn,
                small: small(module),
                badge: badge
            )
        }
    }

    /// Open while this module is the open one; closing it closes only this module.
    private func isOpenBinding(for module: ModuleDescriptor) -> Binding<Bool> {
        Binding(
            get: { openModule == module.id },
            set: { isOpen in
                if isOpen {
                    openModule = module.id
                } else if openModule == module.id {
                    openModule = nil
                }
            }
        )
    }
}

#Preview("ModuleListView") {
    @Previewable @State var openModule: String?
    let modules = [
        ModuleDescriptor(
            id: "notch-hub",
            area: .notch,
            symbol: "rectangle.topthird.inset.filled",
            titleKey: "Notch hub",
            summaryKey: "A panel at the notch.",
            permission: nil
        ),
        ModuleDescriptor(
            id: "timers",
            area: .notch,
            symbol: "timer",
            titleKey: "Timers",
            summaryKey: "Countdowns in the notch hub.",
            permission: nil
        ),
    ]
    let entry = { (module: ModuleDescriptor) in
        SettingsEntry(
            id: "modules.\(module.id)",
            pane: .modules,
            group: "Notch",
            label: module.titleKey,
            summary: module.summaryKey,
            module: module.id
        )
    }
    SettingsGroup {
        ModuleListView(
            modules: modules,
            store: ModuleStore(defaults: UserDefaults(suiteName: "holzBar.preview") ?? .standard, catalog: modules),
            openModule: $openModule,
            entry: entry,
            small: { $0.id == "timers" ? Text(verbatim: "in the hub") : nil },
            parent: { $0.id == "timers" ? "notch-hub" : nil },
            hasSettings: { _ in true },
            settings: { _ in
                Text(verbatim: "Settings of the module.")
            }
        )
    }
    .frame(width: 620)
    .padding()
    .background(HolzBarTheme.Palette.ground)
}
