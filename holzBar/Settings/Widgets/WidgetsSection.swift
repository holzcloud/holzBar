//
//  WidgetsSection.swift
//  holzBar
//

import SwiftUI

/// The Widgets module as a row of its own, with the list of widgets under it while it is on.
///
/// The module is off by default. While it is off holzBar creates no widget, runs no timer and
/// reads no source (D-06, D-16). The row sits in the Menu Bar Layout pane until the settings
/// shell hosts the module list; the view is self-contained and moves there unchanged (D-07).
struct WidgetsModuleSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ModuleRow(
                systemImage: "clock",
                title: Text("Widgets"),
                summary: Text("A clock, the battery and other readouts of your own in the menu bar."),
                isOn: Binding(
                    get: { appState.modules.isEnabled(MenuBarWidgets.moduleID) },
                    set: { isOn in
                        appState.modules.setEnabled(MenuBarWidgets.moduleID, isOn)
                    }
                ),
                isPreview: true
            ) {
                WidgetsSection(widgets: appState.widgets)
            }
        }
        .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
        .holzBarGlass(in: HolzBarTheme.shape(HolzBarTheme.Radius.card))
    }
}

/// The widgets of the menu bar: one row each, an editor under the row that was chosen, a way
/// to add one, at most six (D-05).
struct WidgetsSection: View {
    var widgets: MenuBarWidgets
    @State private var removalID: UUID?
    @State private var editingID: UUID?

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(
            get: { removalID != nil },
            set: { isPresented in
                if !isPresented {
                    removalID = nil
                }
            }
        )
    }

    private var isFull: Bool {
        widgets.definitions.count >= WidgetDefinition.maximumCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            ForEach(widgets.definitions) { definition in
                row(for: definition)
                if editingID == definition.id {
                    editor(for: definition)
                }
                if definition.id != widgets.definitions.last?.id {
                    Divider()
                        .overlay(HolzBarTheme.Palette.stroke)
                }
            }
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Menu("Add Widget", systemImage: "plus") {
                    ForEach(WidgetSource.allCases, id: \.self) { source in
                        Button {
                            add(source)
                        } label: {
                            Self.sourceTitle(source)
                        }
                    }
                    Divider()
                    Button {
                        addButton()
                    } label: {
                        Text("Shortcut Button")
                    }
                }
                .fixedSize()
                .disabled(isFull)
                if isFull {
                    Text("You can add up to six widgets.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                }
            }
        }
        .confirmationDialog("Remove this widget?", isPresented: isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = removalID {
                    if editingID == id {
                        editingID = nil
                    }
                    widgets.removeWidget(id: id)
                }
                removalID = nil
            }
            Button("Cancel", role: .cancel) {
                removalID = nil
            }
        }
    }

    private func row(for definition: WidgetDefinition) -> some View {
        let isEditing = editingID == definition.id
        return HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: definition.kind == .button ? WidgetDefinition.buttonSymbolName : definition.source.symbolName)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                title(for: definition)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                summary(for: definition)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            Spacer(minLength: HolzBarTheme.Spacing.sm)
            Button {
                editingID = isEditing ? nil : definition.id
            } label: {
                Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit"))
            .help("Edit")
        }
        .padding(.vertical, HolzBarTheme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private func editor(for definition: WidgetDefinition) -> some View {
        WidgetEditor(widgets: widgets, id: definition.id) {
            removalID = definition.id
        }
        .padding(.leading, HolzBarTheme.Spacing.xl + HolzBarTheme.Spacing.sm)
        .padding(.bottom, HolzBarTheme.Spacing.xs)
    }

    /// The name of a widget: its source, or its button's title.
    private func title(for definition: WidgetDefinition) -> Text {
        switch definition.kind {
        case .text:
            Self.sourceTitle(definition.source)
        case .button:
            // A title the user typed is shown as it is, never looked up as a string key.
            Text(verbatim: WidgetSpeech.label(for: definition))
        }
    }

    /// The format of a text widget, or the state of a button's Shortcut (D-25).
    private func summary(for definition: WidgetDefinition) -> Text {
        switch definition.kind {
        case .text:
            Text(verbatim: "")
        case .button:
            if let name = widgets.shortcutNames[definition.id] {
                Text(verbatim: name)
            } else {
                Text("Choose a Shortcut")
            }
        }
    }

    /// Adds a button that runs a Shortcut, unless there are six (D-05). Its name is chosen in
    /// its editor, which opens at once.
    private func addButton() {
        let definition = WidgetDefinition.button(title: String(localized: "Shortcut"))
        if widgets.addWidget(definition) {
            editingID = definition.id
        }
    }

    /// Adds a widget of the source with its default format, unless there are six (D-05).
    private func add(_ source: WidgetSource) {
        let definition = WidgetDefinition.text(
            source: source,
            uses24HourClock: WidgetFormat.prefers24HourClock(locale: .current),
            now: .now
        )
        widgets.addWidget(definition)
    }

    /// The name of a source, as the user reads it. ``WidgetSpeech`` says the same names.
    static func sourceTitle(_ source: WidgetSource) -> Text {
        switch source {
        case .dateTime: Text("Date and Time")
        case .battery: Text("Battery")
        case .cpu: Text("CPU Load")
        case .memory: Text("Memory")
        case .uptime: Text("Uptime")
        case .freeDisk: Text("Free Disk Space")
        case .countdown: Text("Countdown")
        }
    }
}
