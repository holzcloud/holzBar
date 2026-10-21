//
//  WidgetsSection.swift
//  holzBar
//

import SwiftUI

/// The widgets of the menu bar: one row each, an editor under the row that was chosen, a way
/// to add one, at most six (D-05). The order of the rows is the order of the list, which a
/// settings export carries; rows are moved with the editor's buttons and, for VoiceOver, with
/// the "Move Up" and "Move Down" actions of every row (D-07). The Modules pane shows it under
/// the Widgets row while the module is on.
struct WidgetsSection: View {
    @Environment(AppState.self) private var appState
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
                    Button {
                        addScript()
                    } label: {
                        Text("Script")
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
        .holzBarConfirmation(
            isPresented: isConfirmingRemoval,
            title: Text("Remove this widget?"),
            confirmTitle: "Remove",
            isDestructive: true
        ) {
            if let id = removalID {
                if editingID == id {
                    editingID = nil
                }
                widgets.removeWidget(id: id)
            }
            removalID = nil
        }
    }

    private func row(for definition: WidgetDefinition) -> some View {
        let isEditing = editingID == definition.id
        return HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: definition.symbolName)
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
            .accessibilityValue(isEditing ? Text("Expanded") : Text("Collapsed"))
            .help("Edit")
        }
        .padding(.vertical, HolzBarTheme.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title(for: definition))
        .accessibilityAction(named: "Move Up") {
            widgets.moveWidget(id: definition.id, by: -1)
        }
        .accessibilityAction(named: "Move Down") {
            widgets.moveWidget(id: definition.id, by: 1)
        }
    }

    private func editor(for definition: WidgetDefinition) -> some View {
        let index = widgets.definitions.firstIndex { $0.id == definition.id } ?? 0
        return WidgetEditor(
            widgets: widgets,
            id: definition.id,
            canMoveUp: index > 0,
            canMoveDown: index < widgets.definitions.count - 1
        ) {
            removalID = definition.id
        }
        .padding(.leading, HolzBarTheme.Spacing.xl + HolzBarTheme.Spacing.sm)
        .padding(.bottom, HolzBarTheme.Spacing.xs)
    }

    /// The name of a widget: its source, its button's title, or "Script".
    private func title(for definition: WidgetDefinition) -> Text {
        switch definition.kind {
        case .text:
            Self.sourceTitle(definition.source)
        case .button, .script:
            // A title the user typed is shown as it is, never looked up as a string key.
            Text(verbatim: WidgetSpeech.label(for: definition))
        }
    }

    /// The format of a text widget, the cleaned name of a script widget's script, or the state of
    /// a button's Shortcut (D-23, D-25). A name from the scripts folder is shown through
    /// ``URLPrompt/displayName(_:)``, as everywhere else (T-12-32).
    private func summary(for definition: WidgetDefinition) -> Text {
        switch definition.kind {
        case .text:
            WidgetEditor.presetTitle(definition.preset)
        case .script:
            if let name = appState.automation.scriptStore.widgetScript(for: definition.id) {
                Text(verbatim: URLPrompt.displayName(name))
            } else {
                Text("Choose a script")
            }
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

    /// Adds a script widget, medium wide and without a symbol, unless there are six (D-05). The
    /// script is chosen in its editor, which opens at once (D-23).
    private func addScript() {
        let definition = WidgetDefinition.script()
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
