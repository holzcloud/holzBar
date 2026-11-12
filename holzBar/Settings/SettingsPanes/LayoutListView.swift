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

    private var editor: LayoutEditor {
        appState.layoutEditor
    }

    private var rows: [MenuBarItem] {
        // Reading the revision makes the list follow every change of the drawing or the bar.
        _ = editor.revision
        return editor.availableSections.flatMap { section in
            editor.items(in: section).filter { !$0.isControlItem }
        }
    }

    var body: some View {
        header
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
            }
        }
        .accessibilityElement(children: .contain)
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
