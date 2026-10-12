//
//  ModuleListView.swift
//  holzBar
//

import SwiftUI

/// The list of optional modules: one glass group per area with a row per module.
///
/// The view knows no module by name. What a row says comes from the closures, and the
/// settings of a module open under its row only while the module is on.
struct ModuleListView<Settings: View>: View {
    private let modules: [ModuleDescriptor]
    private let store: ModuleStore
    private let areaTitle: (ModuleArea) -> Text
    private let title: (ModuleDescriptor) -> Text
    private let summary: (ModuleDescriptor) -> Text
    private let permissionText: (ModulePermission) -> Text
    private let isPermissionGranted: (ModulePermission) -> Bool
    private let emptyTitle: Text
    private let emptyMessage: Text
    private let settings: (ModuleDescriptor) -> Settings

    init(
        modules: [ModuleDescriptor],
        store: ModuleStore,
        areaTitle: @escaping (ModuleArea) -> Text,
        title: @escaping (ModuleDescriptor) -> Text,
        summary: @escaping (ModuleDescriptor) -> Text,
        permissionText: @escaping (ModulePermission) -> Text,
        isPermissionGranted: @escaping (ModulePermission) -> Bool,
        emptyTitle: Text,
        emptyMessage: Text,
        @ViewBuilder settings: @escaping (ModuleDescriptor) -> Settings
    ) {
        self.modules = modules
        self.store = store
        self.areaTitle = areaTitle
        self.title = title
        self.summary = summary
        self.permissionText = permissionText
        self.isPermissionGranted = isPermissionGranted
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.settings = settings
    }

    var body: some View {
        ScrollView {
            if modules.isEmpty {
                EmptyState(systemImage: "square.grid.2x2", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xl) {
                    ForEach(ModuleCatalog.populatedAreas(of: modules), id: \.self) { area in
                        section(for: area)
                    }
                }
                .padding(HolzBarTheme.Spacing.lg)
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
    }

    private func section(for area: ModuleArea) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            areaTitle(area)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                let rows = ModuleCatalog.modules(in: area, of: modules)
                ForEach(rows) { module in
                    row(for: module)
                    if module.id != rows.last?.id {
                        Divider()
                            .overlay(HolzBarTheme.Palette.stroke)
                    }
                }
            }
            .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
            .holzBarGlass(in: HolzBarTheme.shape(HolzBarTheme.Radius.card))
        }
    }

    private func row(for module: ModuleDescriptor) -> some View {
        ModuleRow(
            systemImage: module.symbol,
            title: title(module),
            summary: summary(module),
            isOn: Binding(
                get: { store.isEnabled(module.id) },
                set: { store.setEnabled(module.id, $0) }
            ),
            permission: module.permission.map(permissionText),
            isPermissionGranted: module.permission.map(isPermissionGranted) ?? false
        ) {
            settings(module)
        }
    }
}

#Preview("ModuleListView") {
    let modules = [
        ModuleDescriptor(
            id: "timers",
            area: .notch,
            symbol: "timer",
            titleKey: "Timers",
            summaryKey: "Countdowns in the notch hub.",
            permission: nil
        ),
        ModuleDescriptor(
            id: "calendar",
            area: .notch,
            symbol: "calendar",
            titleKey: "Calendar",
            summaryKey: "Next events and meeting links.",
            permission: .calendar
        ),
        ModuleDescriptor(
            id: "clipboard",
            area: .clipboard,
            symbol: "doc.on.clipboard",
            titleKey: "Clipboard history",
            summaryKey: "Local, opt-in and erasable.",
            permission: nil
        ),
    ]
    return ModuleListView(
        modules: modules,
        store: ModuleStore(defaults: UserDefaults(suiteName: "holzBar.preview") ?? .standard, catalog: modules),
        areaTitle: { Text(verbatim: $0.rawValue.capitalized) },
        title: { Text(verbatim: $0.titleKey) },
        summary: { Text(verbatim: $0.summaryKey) },
        permissionText: { Text(verbatim: "Needs \($0.rawValue)") },
        isPermissionGranted: { _ in false },
        emptyTitle: Text(verbatim: "No modules yet"),
        emptyMessage: Text(verbatim: "Modules arrive with the next releases."),
        settings: { _ in
            Text(verbatim: "Settings of the module.")
                .font(HolzBarTheme.Typography.callout)
        }
    )
    .frame(width: 720, height: 520)
    .background(HolzBarTheme.Palette.ground)
}
