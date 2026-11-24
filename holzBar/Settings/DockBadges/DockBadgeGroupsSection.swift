//
//  DockBadgeGroupsSection.swift
//  holzBar
//

import SwiftUI

/// The Groups of the Dock badges settings, below the list of apps: a group shows several of the
/// chosen apps as one item in the menu bar, with their total, and opens a menu of them. A group is
/// made with New Group… (a name, then the apps through Choose Apps…). An app is in at most one
/// group, so choosing it for another group moves it. The pattern is the Layout pane's
/// `ItemGroupsSection`; the strings are this module's own.
struct DockBadgeGroupsSection: View {
    @Environment(AppState.self) private var appState
    @State private var isNamingGroup = false
    @State private var newGroupName = ""

    var body: some View {
        let settings = appState.settings.dockBadges
        VStack(alignment: .leading, spacing: 0) {
            header
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
        SettingsValueRow(Text(verbatim: group.name), value: Text("\(members.count) apps"))
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
    }

    /// The chosen apps, the ones a group can hold, with their names.
    private func appRows(settings: DockBadgesSettings) -> [DockAppRow] {
        appState.dockBadges.rows(chosen: settings.apps).filter(\.isChosen)
    }
}
