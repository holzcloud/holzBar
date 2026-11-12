//
//  AboutCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the About pane, in the order the pane shows them. The first
    /// group has no header; its entries use the pane's title as their group.
    enum AboutPane {
        static let about = String(localized: "About")
        static let updating = String(localized: "Updating")
        static let more = String(localized: "More")

        static let entries: [SettingsEntry] = [
            .aboutVersion,
            .aboutWebsite,
            .aboutRepository,
            .aboutReportBug,
            .aboutBasedOnIce,
            .aboutHowToUpdate,
            .aboutWhatsNew,
            .aboutIntroduction,
            .aboutAcknowledgements,
            .aboutDiagnostics,
            .aboutQuit,
        ]
    }
}

extension SettingsEntry {
    static let aboutVersion = SettingsEntry(
        id: "aboutVersion",
        pane: .about,
        group: SettingsCatalog.AboutPane.about,
        label: String(localized: "Version")
    )

    static let aboutWebsite = SettingsEntry(
        id: "aboutWebsite",
        pane: .about,
        group: SettingsCatalog.AboutPane.about,
        label: String(localized: "Website")
    )

    static let aboutRepository = SettingsEntry(
        id: "aboutRepository",
        pane: .about,
        group: SettingsCatalog.AboutPane.about,
        label: String(localized: "Repository"),
        info: String(localized: "Opens holzBar's repository on GitHub in the browser.")
    )

    static let aboutReportBug = SettingsEntry(
        id: "aboutReportBug",
        pane: .about,
        group: SettingsCatalog.AboutPane.about,
        label: String(localized: "Report a bug")
    )

    static let aboutBasedOnIce = SettingsEntry(
        id: "aboutBasedOnIce",
        pane: .about,
        group: SettingsCatalog.AboutPane.about,
        label: String(localized: "Based on Ice by Jordan Baird")
    )

    static let aboutHowToUpdate = SettingsEntry(
        id: "aboutHowToUpdate",
        pane: .about,
        group: SettingsCatalog.AboutPane.updating,
        label: String(localized: "How to Update holzBar…"),
        info: String(localized: "holzBar never connects to the network and never looks for updates itself. The button opens the release notes in the browser.")
    )

    static let aboutWhatsNew = SettingsEntry(
        id: "aboutWhatsNew",
        pane: .about,
        group: SettingsCatalog.AboutPane.more,
        label: String(localized: "What's new in this version")
    )

    static let aboutIntroduction = SettingsEntry(
        id: "aboutIntroduction",
        pane: .about,
        group: SettingsCatalog.AboutPane.more,
        label: String(localized: "Introduction to holzBar"),
        info: String(localized: "The three short steps of the first launch: what holzBar does, how to show hidden items and how to arrange your menu bar.")
    )

    static let aboutAcknowledgements = SettingsEntry(
        id: "aboutAcknowledgements",
        pane: .about,
        group: SettingsCatalog.AboutPane.more,
        label: String(localized: "Acknowledgements"),
        info: String(localized: "holzBar's license (GPL-3.0), the original Ice and the open-source packages it uses.")
    )

    static let aboutDiagnostics = SettingsEntry(
        id: "aboutDiagnostics",
        pane: .about,
        group: SettingsCatalog.AboutPane.more,
        label: String(localized: "Diagnostics"),
        info: String(localized: "Nothing is sent. The report holds only versions and counts: no names of items, apps, profiles or networks, and no paths.")
    )

    static let aboutQuit = SettingsEntry(
        id: "aboutQuit",
        pane: .about,
        group: SettingsCatalog.AboutPane.more,
        label: String(localized: "Quit holzBar")
    )
}
