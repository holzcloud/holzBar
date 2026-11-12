//
//  LayoutListView.swift
//  holzBar
//

import SwiftUI

/// The list view of Layout: every item with its app and a pop-up for its section (D-08).
///
/// The pop-up moves an item through `LayoutEditor.moveFromPane(_:to:)`, the path of a drag, so
/// draft mode, "Apply changes immediately", rules and undo behave as in the bars. It is also
/// the keyboard and VoiceOver way to arrange the items (D-10). The sections come in the bars'
/// order, the items in their bar order; holzBar's own control items are not listed.
struct LayoutListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    /// The row whose pop-up has the keyboard focus, which highlights its app like the pointer.
    @FocusState private var focusedRow: CGWindowID?

    private var editor: LayoutEditor {
        appState.layoutEditor
    }

    private var rows: [MenuBarItem] {
        // Reading the revision makes the list follow every change of the drawing or the bar.
        _ = editor.revision
        let filter = appState.navigationState.layoutFilter
        return editor.availableSections.flatMap { section in
            editor.items(in: section).filter { item in
                !item.isControlItem && LayoutListFilter.matches(
                    query: filter,
                    itemName: item.displayName,
                    appName: item.sourceApplication?.localizedName
                )
            }
        }
    }

    var body: some View {
        let rows = rows
        header
        if rows.isEmpty, !appState.navigationState.layoutFilter.isEmpty {
            SettingsEmptyRow(systemImage: "line.3.horizontal.decrease.circle", Text("No item matches the filter.")) {
                Button("Clear Filter") {
                    appState.navigationState.layoutFilter = ""
                }
            }
        }
        ForEach(rows, id: \.tag) { item in
            row(for: item)
        }
    }

    private var header: some View {
        SettingsBlockRow {
            HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                Color.clear
                    .frame(width: HolzBarTheme.LayoutList.iconSize, height: 1)
                Text("Item")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("App")
                    .frame(width: HolzBarTheme.LayoutList.appColumnWidth, alignment: .leading)
                Text("Section")
                    .frame(width: HolzBarTheme.LayoutList.sectionColumnWidth, alignment: .leading)
            }
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        }
        // Each row says its own columns.
        .accessibilityHidden(true)
    }

    private func row(for item: MenuBarItem) -> some View {
        SettingsBlockRow {
            HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                picture(of: item)
                Text(verbatim: item.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: item.sourceApplication?.localizedName ?? "")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .frame(width: HolzBarTheme.LayoutList.appColumnWidth, alignment: .leading)
                sectionPicker(for: item)
                    .frame(width: HolzBarTheme.LayoutList.sectionColumnWidth, alignment: .leading)
                    .focused($focusedRow, equals: item.windowID)
            }
        }
        .background {
            // On macOS 27 the rows of the app under the pointer are tinted together (D-11).
            if let app = editor.highlightedApp, item.layoutKey27 == app {
                HolzBarTheme.Palette.accent.opacity(tintOpacity)
            }
        }
        .onHover { isInside in
            if isInside {
                editor.highlightApp(of: item)
            } else {
                editor.clearHighlight(of: item)
            }
        }
        .onChange(of: focusedRow == item.windowID) { _, isFocused in
            if isFocused {
                editor.highlightApp(of: item)
            } else {
                editor.clearHighlight(of: item)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var tintOpacity: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.accentFillDark
            : HolzBarTheme.SettingsKit.accentFillLight
    }

    @ViewBuilder
    private func picture(of item: MenuBarItem) -> some View {
        Group {
            if let image = appState.itemIconStore.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: HolzBarTheme.LayoutList.iconSize, height: HolzBarTheme.LayoutList.iconSize)
        .accessibilityHidden(true)
    }

    private func sectionPicker(for item: MenuBarItem) -> some View {
        let selection = Binding<MenuBarSection.Name?>(
            get: { editor.section(of: item) },
            set: { section in
                guard let section, section != editor.section(of: item) else {
                    return
                }
                if !editor.moveFromPane(item, to: section) {
                    NSSound.beep()
                }
            }
        )
        return Picker(selection: selection) {
            ForEach(editor.availableSections, id: \.self) { name in
                Text(verbatim: name.displayString).tag(Optional(name))
            }
        } label: {
            Text("Section of \(item.displayName)")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(!editor.canMoveFromPane(item))
        .help(editor.paneMoveRefusal(for: item).map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityLabel(Text("Section of \(item.displayName)"))
    }
}
