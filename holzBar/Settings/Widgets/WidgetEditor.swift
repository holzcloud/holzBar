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
/// D-15). A button offers its title or symbol and the name of its Shortcut (D-20, D-21).
/// Every change goes through ``MenuBarWidgets/update(_:)``, so the menu bar follows at once.
struct WidgetEditor: View {
    var widgets: MenuBarWidgets
    let id: UUID
    let onRemove: () -> Void

    private var definition: WidgetDefinition? {
        widgets.definitions.first { $0.id == id }
    }

    var body: some View {
        if let definition {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                switch definition.kind {
                case .text:
                    EmptyView()
                case .button:
                    ShortcutButtonFields(widgets: widgets, id: id)
                }
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Spacer(minLength: HolzBarTheme.Spacing.sm)
                    Button("Remove", role: .destructive, action: onRemove)
                }
                .padding(.top, HolzBarTheme.Spacing.xs)
            }
        }
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
