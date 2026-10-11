//
//  WidgetEditor.swift
//  holzBar
//

import SwiftUI

/// The editor of one widget, shown under its row in the widget list: every option the widget's
/// source or kind has, the place in the list and the way to remove it.
///
/// A text widget offers its source, its format (a fixed preset, no template language), the
/// leading symbol, and the options of its source: the clock's hour cycle and seconds, the
/// countdown's moment, and the refresh interval of CPU and memory (D-02, D-09, D-10, D-11,
/// D-15). A button offers its title or symbol and the name of its Shortcut (D-20, D-21). A
/// script widget offers one of the scripts of the scripts folder, a fixed width and the symbol
/// (D-23). Every change goes through ``MenuBarWidgets/update(_:)``, so the menu bar follows at
/// once.
struct WidgetEditor: View {
    var widgets: MenuBarWidgets
    let id: UUID
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onRemove: () -> Void

    private var definition: WidgetDefinition? {
        widgets.definitions.first { $0.id == id }
    }

    var body: some View {
        if let definition {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                switch definition.kind {
                case .text:
                    TextWidgetFields(widgets: widgets, definition: definition)
                case .button:
                    ShortcutButtonFields(widgets: widgets, id: id)
                case .script:
                    ScriptWidgetFields(widgets: widgets, definition: definition)
                }
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Button("Move Up", systemImage: "arrow.up") {
                        widgets.moveWidget(id: id, by: -1)
                    }
                    .disabled(!canMoveUp)
                    Button("Move Down", systemImage: "arrow.down") {
                        widgets.moveWidget(id: id, by: 1)
                    }
                    .disabled(!canMoveDown)
                    Spacer(minLength: HolzBarTheme.Spacing.sm)
                    Button("Remove", role: .destructive, action: onRemove)
                }
                .padding(.top, HolzBarTheme.Spacing.xs)
            }
        }
    }

    /// The name of a format, as the user reads it.
    static func presetTitle(_ preset: WidgetPreset) -> Text {
        switch preset {
        case .time: Text("Time")
        case .weekdayAndTime: Text("Weekday and Time")
        case .dateAndTime: Text("Date and Time")
        case .weekdayDateAndTime: Text("Weekday, Date and Time")
        case .percent: Text("Percent")
        case .percentAndState: Text("Percent and State")
        case .percentUsed: Text("Percent Used")
        case .gigabytesUsed: Text("Gigabytes Used")
        case .gigabytesFree: Text("Gigabytes Free")
        case .percentFree: Text("Percent Free")
        case .duration: Text("Duration")
        case .compactDuration: Text("Compact Duration")
        case .narrowText: Text("Narrow")
        case .mediumText: Text("Medium")
        case .wideText: Text("Wide")
        }
    }
}

// MARK: - Text widgets

/// The options of a text widget. The definition is read again from the widgets, so an edit
/// that was refused (a countdown too far away) leaves the controls on the stored value.
private struct TextWidgetFields: View {
    var widgets: MenuBarWidgets
    let definition: WidgetDefinition

    var body: some View {
        Picker("Source", selection: sourceBinding) {
            ForEach(WidgetSource.allCases, id: \.self) { source in
                WidgetsSection.sourceTitle(source)
                    .tag(source)
            }
        }
        if definition.source.presets.count > 1 {
            Picker("Format", selection: binding(\.preset)) {
                ForEach(definition.source.presets, id: \.self) { preset in
                    WidgetEditor.presetTitle(preset)
                        .tag(preset)
                }
            }
        }
        Toggle("Show symbol", isOn: binding(\.showsSymbol))
        if definition.source == .dateTime {
            Toggle("24-hour clock", isOn: binding(\.uses24HourClock))
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Toggle("Show seconds", isOn: binding(\.showsSeconds))
                    .help("Wakes the Mac every second while visible.")
                Text("Wakes the Mac every second while visible.")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if definition.source == .countdown {
            DatePicker(
                "Count down to",
                selection: countdownBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
        if !refreshChoices.isEmpty {
            Picker("Refresh every", selection: binding(\.refreshSeconds)) {
                ForEach(refreshChoices, id: \.self) { seconds in
                    Text("\(seconds) s")
                        .tag(Optional(seconds))
                }
            }
        }
    }

    /// The intervals of the source, and the stored one when it is not among them (a settings
    /// file may hold any value within the range).
    private var refreshChoices: [Int] {
        var choices = definition.source.refreshChoices
        if let stored = definition.refreshSeconds, !choices.isEmpty, !choices.contains(stored) {
            choices.append(stored)
            choices.sort()
        }
        return choices
    }

    /// A change of the source starts with the source's own format and interval, and a
    /// countdown with a moment an hour from now.
    private var sourceBinding: Binding<WidgetSource> {
        Binding(
            get: { definition.source },
            set: { source in
                guard source != definition.source else {
                    return
                }
                let fresh = WidgetDefinition.text(
                    source: source,
                    uses24HourClock: definition.uses24HourClock,
                    now: .now
                )
                var updated = definition
                updated.source = source
                updated.preset = fresh.preset
                updated.refreshSeconds = fresh.refreshSeconds
                updated.countdownTarget = fresh.countdownTarget
                widgets.update(updated)
            }
        )
    }

    /// The countdown's moment, to the minute.
    private var countdownBinding: Binding<Date> {
        Binding(
            get: { definition.countdownTarget ?? .now },
            set: { date in
                var updated = definition
                updated.countdownTarget = Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
                widgets.update(updated)
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WidgetDefinition, Value>) -> Binding<Value> {
        Binding(
            get: { definition[keyPath: keyPath] },
            set: { value in
                var updated = definition
                updated[keyPath: keyPath] = value
                widgets.update(updated)
            }
        )
    }
}

// MARK: - Script widgets

/// The options of a script widget: the script it runs, its fixed width and the symbol (D-23).
///
/// The script is one of the scripts of the scripts folder, listed by its cleaned name
/// (T-12-32). The choice is stored by ``ScriptStore/setWidgetScript(_:for:)`` on this Mac only;
/// the definition holds no script name, so nothing that exports, imports or shares widgets
/// carries it (D-25). Choosing a script does not allow it: a script that is not allowed, or
/// that changed since, says so here and sends the user to Automation, Scripts.
private struct ScriptWidgetFields: View {
    @Environment(AppState.self) private var appState
    var widgets: MenuBarWidgets
    let definition: WidgetDefinition

    private var store: ScriptStore {
        appState.automation.scriptStore
    }

    private var chosenName: String? {
        store.widgetScript(for: definition.id)
    }

    /// The scripts to choose from: those the gate can ever allow, and the chosen one when it is
    /// not among them (deleted, or refused since), so the row keeps saying what it is for.
    private var scriptNames: [String] {
        var names = store.scripts.compactMap { entry -> String? in
            if case .refused = entry.decision {
                return nil
            }
            return entry.name
        }
        if let chosenName, !names.contains(chosenName) {
            names.append(chosenName)
        }
        return names
    }

    /// Whether the chosen script does not run now: not allowed, changed since, refused or gone.
    /// The widget shows an en dash then (D-13), and the widget's VoiceOver value says the same.
    private var isNotAllowed: Bool {
        guard let chosenName else {
            return false
        }
        guard let entry = store.scripts.first(where: { $0.name == chosenName }) else {
            return true
        }
        if case .allowed = entry.decision {
            return false
        }
        return true
    }

    var body: some View {
        Picker("Script", selection: scriptBinding) {
            Text("None").tag(String?.none)
            ForEach(scriptNames, id: \.self) { name in
                Text(verbatim: URLPrompt.displayName(name)).tag(String?.some(name))
            }
        }
        if isNotAllowed {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text("Allow this script first in Automation, Scripts.")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Scripts") {
                    appState.navigationState.settingsNavigationIdentifier = .automation
                }
            }
        }
        Picker("Width", selection: binding(\.preset)) {
            ForEach(WidgetKind.scriptPresets, id: \.self) { preset in
                WidgetEditor.presetTitle(preset)
                    .tag(preset)
            }
        }
        Toggle("Show symbol", isOn: binding(\.showsSymbol))
        Text("The widget shows the first line of the script's output. It runs when the widget appears and when you click it, and on the system events your automation rules follow, never on a timer.")
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The chosen script, read from the store and written to it. A new choice asks the script
    /// at once, so the widget shows its line without waiting for a click (the user's own action
    /// skips only the 30 seconds between two runs; the gate and the run limit still apply).
    private var scriptBinding: Binding<String?> {
        Binding(
            get: { chosenName },
            set: { name in
                store.setWidgetScript(name, for: definition.id)
                widgets.refreshScriptWidget(id: definition.id)
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WidgetDefinition, Value>) -> Binding<Value> {
        Binding(
            get: { definition[keyPath: keyPath] },
            set: { value in
                var updated = definition
                updated[keyPath: keyPath] = value
                widgets.update(updated)
            }
        )
    }
}

// MARK: - Buttons

/// The options of a Shortcut button: its title or the symbol, and the Shortcut's name. The name
/// is typed, because no public API lists a person's Shortcuts without a permission, and stays
/// on this Mac (D-21, D-25).
private struct ShortcutButtonFields: View {
    var widgets: MenuBarWidgets
    let id: UUID

    @State private var title: String
    @State private var shortcutName: String
    @State private var isNameRefused = false

    init(widgets: MenuBarWidgets, id: UUID) {
        self.widgets = widgets
        self.id = id
        _title = State(initialValue: widgets.definitions.first { $0.id == id }?.buttonTitle ?? "")
        _shortcutName = State(initialValue: widgets.shortcutNames[id] ?? "")
    }

    private var definition: WidgetDefinition? {
        widgets.definitions.first { $0.id == id }
    }

    var body: some View {
        TextField("Title", text: $title)
            .textFieldStyle(.roundedBorder)
            .onChange(of: title) { _, newValue in
                commitTitle(newValue)
            }
        Toggle(
            "Show as symbol",
            isOn: Binding(
                get: { definition?.buttonShowsSymbol ?? true },
                set: { showsSymbol in
                    guard var updated = definition else {
                        return
                    }
                    updated.buttonShowsSymbol = showsSymbol
                    widgets.update(updated)
                }
            )
        )
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            TextField("Shortcut name", text: $shortcutName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: shortcutName) { _, newValue in
                    isNameRefused = !widgets.setShortcutName(newValue, for: id)
                }
            Text("Type the name exactly as it appears in the Shortcuts app.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if isNameRefused {
                Text("This name cannot be used.")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Stores the title as it is typed, without writing the cleaned title back into the field,
    /// so a space between two words can be typed.
    private func commitTitle(_ text: String) {
        if text.count > WidgetDefinition.maximumTitleLength {
            title = String(text.prefix(WidgetDefinition.maximumTitleLength))
            return
        }
        guard var updated = definition else {
            return
        }
        updated.buttonTitle = WidgetDefinition.cleanedTitle(text)
        widgets.update(updated)
    }
}
