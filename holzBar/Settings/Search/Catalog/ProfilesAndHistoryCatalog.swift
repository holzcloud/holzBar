//
//  ProfilesAndHistoryCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Profiles & History pane, in the order the pane shows them.
    enum ProfilesAndHistoryPane {
        static let profiles = String(localized: "Profiles")
        static let groups = String(localized: "Groups")
        static let spacers = String(localized: "Spacers")
        static let layoutHistory = String(localized: "Layout history")
        /// The id of the pane's one disclosure (D-20); not a user-visible string.
        static let snapshotsDisclosure = "profilesAndHistory.snapshots"

        static let entries: [SettingsEntry] = [
            .profilesSaveAsProfile,
            .profilesImport,
            .profilesNewGroup,
            .profilesSpacerCount,
            .profilesSpacerWidth,
            .profilesKeepHistory,
            .profilesSnapshotsToKeep,
        ]
    }
}

extension SettingsEntry {
    static let profilesSaveAsProfile = SettingsEntry(
        id: "profilesSaveAsProfile",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.profiles,
        label: String(localized: "Current layout"),
        info: String(localized: "Save the current layout as a profile, for example \u{201C}Work\u{201D} or \u{201C}Home\u{201D}. A profile with the same name is replaced. Apply it later from here, or with holzbar://profile/<name>.")
    )

    static let profilesImport = SettingsEntry(
        id: "profilesImport",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.profiles,
        label: String(localized: "Profile from a file"),
        info: String(localized: "Importing adds the profile only. It moves nothing until you apply it.")
    )

    static let profilesNewGroup = SettingsEntry(
        id: "profilesNewGroup",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.groups,
        label: String(localized: "Bundle items"),
        info: String(localized: "A group puts several items behind an icon of its own.")
    )

    static let profilesSpacerCount = SettingsEntry(
        id: "profilesSpacerCount",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.spacers,
        label: String(localized: "Number"),
        info: String(localized: "Empty items that add space between others. ⌘ Command-drag them where you want them, or arrange them in Layout. At most ten.")
    )

    static let profilesSpacerWidth = SettingsEntry(
        id: "profilesSpacerWidth",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.spacers,
        label: String(localized: "Width"),
        info: nil
    )

    static let profilesKeepHistory = SettingsEntry(
        id: "profilesKeepHistory",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.layoutHistory,
        label: String(localized: "Keep a history of the layout"),
        info: nil
    )

    static let profilesSnapshotsToKeep = SettingsEntry(
        id: "profilesSnapshotsToKeep",
        pane: .profilesAndHistory,
        group: SettingsCatalog.ProfilesAndHistoryPane.layoutHistory,
        label: String(localized: "Snapshots to keep"),
        info: String(localized: "Older ones are deleted. Starred snapshots stay and are not counted.")
    )
}
