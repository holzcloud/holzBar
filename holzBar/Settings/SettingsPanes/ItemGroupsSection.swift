//
//  ItemGroupsSection.swift
//  holzBar
//

import SwiftUI

/// Creates groups of items behind icons of their own (jordanbaird/Ice#46).
struct ItemGroupsSection: View {
    @Environment(AppState.self) private var appState
    var groups: MenuBarItemGroups
    var itemManager: MenuBarItemManager
    @State private var isNamingGroup = false
    @State private var newGroupName = ""

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems.filter { !$0.isControlItem }
    }

    /// The group's color for the color well; the primary color while it has none.
    private func colorBinding(for group: MenuBarItemGroup) -> Binding<CGColor> {
        Binding {
            (group.color ?? NSColor.labelColor).cgColor
        } set: { color in
            groups.setColor(NSColor(cgColor: color), for: group)
        }
    }

    /// The name of one of the group symbols, for the symbol menu and VoiceOver.
    private func symbolTitle(_ symbolName: String) -> Text {
        switch symbolName {
        case "square.grid.2x2": Text("Apps")
        case "folder": Text("Folder")
        case "tray": Text("Tray")
        case "briefcase": Text("Work")
        case "house": Text("Home")
        case "gamecontroller": Text("Games")
        case "music.note": Text("Music")
        case "network": Text("Network")
        case "bolt": Text("Power")
        case "cloud": Text("Cloud")
        case "wrench.and.screwdriver": Text("Tools")
        case "star": Text("Favorites")
        default: Text(verbatim: symbolName)
        }
    }

    var body: some View {
        SettingsGroup(SettingsCatalog.ProfilesAndHistoryPane.groups) {
            ForEach(groups.groups) { group in
                groupRows(for: group)
            }
            SettingsButtonRow(.profilesNewGroup) {
                Button("New Group…") {
                    newGroupName = ""
                    isNamingGroup = true
                }
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Name", text: $newGroupName)
                Button("Create") {
                    groups.addGroup(named: newGroupName)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        // The pane reads the item list once when it appears, and only when it changed; the
        // manager keeps it current on events of its own, and no concealment is touched.
        .task {
            await itemManager.cacheItemsIfNeeded()
        }
    }

    /// The rows of one group: its name and count, then the sub rows.
    @ViewBuilder
    private func groupRows(for group: MenuBarItemGroup) -> some View {
        SettingsValueRow(Text(verbatim: group.name), value: Text("\(group.itemTags.count) items"))
        SettingsButtonRow(Text("Group symbol")) {
            Menu {
                ForEach(MenuBarItemGroups.symbolNames, id: \.self) { symbol in
                    Button {
                        groups.setSymbol(symbol, for: group)
                    } label: {
                        Label {
                            symbolTitle(symbol)
                        } icon: {
                            Image(systemName: symbol)
                        }
                    }
                }
                Divider()
                Button("Choose Image…") {
                    groups.chooseImage(for: group)
                }
                Button("Use Symbol") {
                    groups.useSymbol(for: group)
                }
                .disabled(group.imageFile == nil)
            } label: {
                Label {
                    symbolTitle(group.symbolName)
                } icon: {
                    Image(systemName: group.symbolName)
                }
            }
            .fixedSize()
        }
        .settingsSubRow()
        SettingsColorRow(
            Text("Color"),
            color: colorBinding(for: group),
            supportsOpacity: false,
            info: Text("The color of the group's icon and name")
        )
        .settingsSubRow()
        if group.colorHex != nil {
            SettingsButtonRow {
                Button("Remove Color") {
                    groups.setColor(nil, for: group)
                }
            }
            .settingsSubRow()
        }
        SettingsButtonRow(Text("Items")) {
            Menu("Choose…") {
                ForEach(items, id: \.tag) { item in
                    // swiftlint:disable:next design_settings_bare_toggle - a Toggle in a Menu is a checkmark item, not a switch
                    Toggle(item.displayName, isOn: Binding(
                        get: { groups.contains(item, in: group) },
                        set: { _ in groups.toggle(item, in: group) }
                    ))
                }
            }
            .fixedSize()
        }
        .settingsSubRow()
        SettingsButtonRow {
            Button("Delete", role: .destructive) {
                // Acts at once; the undo toast brings the group back with its image (D-04).
                guard let removed = groups.deleteGroup(group) else {
                    return
                }
                appState.layoutUndo.recordDeletion(
                    String(localized: "\u{201C}\(group.name)\u{201D} deleted"),
                    place: .settings,
                    restore: { groups.reinsertGroup(removed.group, at: removed.index) },
                    deleteAgain: { groups.deleteGroup(removed.group) },
                    onDiscard: { groups.discardImage(of: removed.group) }
                )
            }
        }
        .settingsSubRow()
    }
}
