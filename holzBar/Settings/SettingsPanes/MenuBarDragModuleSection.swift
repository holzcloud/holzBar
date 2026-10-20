//
//  MenuBarDragModuleSection.swift
//  holzBar
//

import SwiftUI

/// The Drag in the Menu Bar module as a row of its own, in the Menu Bar Layout pane.
///
/// The module is off by default. While it is off holzBar runs no tap for it. On macOS 27 the row
/// also says how to hide an app by dragging its item.
struct MenuBarDragModuleSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ModuleRow(
                systemImage: "arrow.left.arrow.right",
                title: Text("Drag in the Menu Bar"),
                summary: Text("Move menu bar items by dragging them, without holding ⌘ Command."),
                isOn: Binding(
                    get: { appState.modules.isEnabled(MenuBarDragController.moduleID) },
                    set: { isOn in
                        appState.modules.setEnabled(MenuBarDragController.moduleID, isOn)
                    }
                )
            ) {
                if #available(macOS 27.0, *) {
                    Text("Drop an item on the holzBar icon to hide its app.")
                        .font(HolzBarTheme.Typography.callout)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
        .holzBarGlass(in: HolzBarTheme.shape(HolzBarTheme.Radius.card))
    }
}
