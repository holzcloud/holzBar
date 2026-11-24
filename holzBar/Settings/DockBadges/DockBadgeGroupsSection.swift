//
//  DockBadgeGroupsSection.swift
//  holzBar
//

import SwiftUI

/// The Groups of the Dock badges settings, below the list of apps: a group shows several of the
/// chosen apps as one item in the menu bar, with their total, and opens a menu of them. A group is
/// made with New Group… (a name, then the apps through Choose Apps…), renamed in its Name row and
/// deleted with Delete Group, which acts at once and offers Undo. An app is in at most one group,
/// so choosing it for another group moves it. With no group a row says what a group is. The
/// pattern is the Layout pane's `ItemGroupsSection`; the strings are this module's own.
struct DockBadgeGroupsSection: View {
    @Environment(AppState.self) private var appState
    @State private var isNamingGroup = false
    @State private var newGroupName = ""

    var body: some View {
        let settings = appState.settings.dockBadges
        VStack(alignment: .leading, spacing: 0) {
            header
            if settings.groups.isEmpty {
                SettingsEmptyRow(
                    systemImage: "square.grid.2x2",
                    Text("No groups yet: a group shows several apps as one item with their total.")
                )
            }
            ForEach(settings.groups) { group in
                groupRows(for: group, settings: settings)
            }
            SettingsButtonRow(unlabeled: .modulesDockBadgesNewGroup) {
                Button("New Group…") {
                    newGroupName = ""
                    isNamingGroup = true
                }
                .disabled(settings.groups.count >= DockBadgeGroupList.maximumCount)
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Name", text: $newGroupName)
                Button("Create Group") {
                    settings.addGroup(named: newGroupName)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    /// The header of the section, laid out as a row of the open area.
    private var header: some View {
        Text("Groups")
            .font(HolzBarTheme.Typography.callout.weight(.semibold))
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome()
    }

    /// The rows of one group: its name and the number of its apps, then the sub rows.
    @ViewBuilder
    private func groupRows(for group: DockBadgeGroup, settings: DockBadgesSettings) -> some View {
        let members = group.apps.filter(settings.isChosen)
        // One line with the tail cut; the whole name is the tooltip and, as the row's label, what
        // VoiceOver reads.
        SettingsValueRow(Text(verbatim: group.name), value: Text("\(members.count) apps"))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(group.name)
        GroupNameRow(group: group, settings: settings)
        SettingsButtonRow(Text("Apps")) {
            Menu("Choose Apps…") {
                ForEach(appRows(settings: settings)) { row in
                    // swiftlint:disable:next design_settings_bare_toggle - a Toggle in a Menu is a checkmark item, not a switch
                    Toggle(row.name, isOn: Binding(
                        get: { settings.group(group.id)?.apps.contains(row.bundleID) ?? false },
                        set: { settings.setMember(row.bundleID, of: group.id, isMember: $0) }
                    ))
                }
            }
            .fixedSize()
            .disabled(appRows(settings: settings).isEmpty)
        }
        .settingsSubRow()
        SettingsButtonRow {
            Button("Delete Group", role: .destructive) {
                delete(group, settings: settings)
            }
        }
        .settingsSubRow()
    }

    /// Deletes a group at once; its apps stay chosen and show as items of their own. The undo toast
    /// brings the group back at its place, without the apps another group took since.
    private func delete(_ group: DockBadgeGroup, settings: DockBadgesSettings) {
        guard let removed = settings.deleteGroup(group.id) else {
            return
        }
        appState.layoutUndo.recordDeletion(
            String(localized: "\u{201C}\(group.name)\u{201D} deleted"),
            place: .settings,
            restore: { settings.reinsertGroup(removed.group, at: removed.index) },
            deleteAgain: { settings.deleteGroup(removed.group.id) }
        )
    }

    /// The chosen apps, the ones a group can hold, with their names.
    private func appRows(settings: DockBadgesSettings) -> [DockAppRow] {
        appState.dockBadges.rows(chosen: settings.apps).filter(\.isChosen)
    }
}

/// The Name row of a group. The name is edited in a draft and renames the group when the user
/// presses Return or leaves the pane; an empty name keeps the old one, which the field then shows.
private struct GroupNameRow: View {
    let group: DockBadgeGroup
    let settings: DockBadgesSettings
    @State private var draft: String

    init(group: DockBadgeGroup, settings: DockBadgesSettings) {
        self.group = group
        self.settings = settings
        _draft = State(initialValue: group.name)
    }

    var body: some View {
        SettingsTextFieldRow(Text("Name"), text: $draft)
            .onSubmit(commit)
            .onChange(of: group.name) { _, name in
                draft = name
            }
            .onDisappear(perform: commit)
            .settingsSubRow()
    }

    private func commit() {
        settings.rename(group.id, to: draft)
        if let name = settings.group(group.id)?.name, name != draft {
            draft = name
        }
    }
}
