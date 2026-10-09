//
//  ModuleGalleryView.swift
//  holzBar
//

import SwiftUI

/// The gallery of optional modules: a grid of cards, one per module, grouped by area.
///
/// The view knows no module by name. What a card says comes from the closures, and the
/// settings of a module are shown below its card only while the module is on.
struct ModuleGalleryView<Settings: View>: View {
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

    private let columns = [
        GridItem(.adaptive(minimum: 300), spacing: HolzBarTheme.Spacing.md, alignment: .top)
    ]

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
            LazyVGrid(columns: columns, spacing: HolzBarTheme.Spacing.md) {
                ForEach(ModuleCatalog.modules(in: area, of: modules)) { module in
                    card(for: module)
                }
            }
        }
    }

    private func card(for module: ModuleDescriptor) -> some View {
        ModuleCard(
            systemImage: module.symbol,
            title: title(module),
            summary: summary(module),
            isOn: Binding(
                get: { store.isEnabled(module.id) },
                set: { store.setEnabled(module.id, $0) }
            ),
            permission: module.permission.map { permission in
                PermissionPill(
                    permissionText(permission),
                    state: isPermissionGranted(permission) ? .granted : .needed
                )
            }
        ) {
            settings(module)
        }
    }
}

#Preview("ModuleGalleryView") {
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
        )
    ]
    return ModuleGalleryView(
        modules: modules,
        store: ModuleStore(defaults: UserDefaults(suiteName: "holzBar.preview") ?? .standard, catalog: modules),
        areaTitle: { Text(verbatim: $0.rawValue.capitalized) },
        title: { Text(verbatim: $0.titleKey) },
        summary: { Text(verbatim: $0.summaryKey) },
        permissionText: { Text(verbatim: "Needs \($0.rawValue)") },
        isPermissionGranted: { _ in false },
        emptyTitle: Text(verbatim: "No modules yet"),
        emptyMessage: Text(verbatim: "Modules arrive with the next releases.")
    ) { _ in
        Text(verbatim: "Settings of the module.")
            .font(HolzBarTheme.Typography.callout)
    }
    .frame(width: 720, height: 520)
    .background(HolzBarTheme.Palette.ground)
}
