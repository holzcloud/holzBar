//
//  LayoutNotShownGroup.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The group Not shown by macOS of the Layout pane (Phase 97, D-13, D-18, concept M7): the apps
/// macOS does not show in the menu bar, one row each with the reason and one link to the place
/// that fixes it. holzBar hides none of them; the footnote says so.
///
/// The group is absent while there is no such app. Each fix only opens something: Finder with the
/// file selected, or the Menu Bar pane of System Settings. When a fix cannot open, nothing happens
/// and the row keeps its reason.
@available(macOS 27.0, *)
struct NotShownGroup: View {
    let list: NotShownList27

    var body: some View {
        if !list.rows.isEmpty {
            SettingsGroup(
                SettingsCatalog.LayoutPane.notShown,
                footnote: Text("macOS decides what the menu bar shows. These apps are hidden by macOS, not by holzBar.")
            ) {
                ForEach(list.rows) { row in
                    SettingsButtonRow(
                        Text(verbatim: row.name),
                        small: row.reason.title,
                        badge: .preview,
                        info: row.reason.info
                    ) {
                        Button {
                            open(row)
                        } label: {
                            row.fix.label
                        }
                    }
                }
            }
        }
    }

    /// Opens the fix of a row, or does nothing when it cannot: the file is gone, the row has no
    /// path, or the link does not open. Never writes a System Settings preference.
    private func open(_ row: NotShownApps.Row) {
        switch row.fix {
        case .showInFinder:
            guard let path = row.path, FileManager.default.fileExists(atPath: path) else {
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .openMenuBarSettings:
            guard let url = URL(string: NotShownApps.menuBarSettingsURL) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}

private extension NotShownApps.Reason {
    /// The short reason under the app's name.
    var title: Text {
        switch self {
        case .notInApplications:
            Text("Not in Applications")
        case .noAppIdentifier:
            Text("No app identifier")
        case .mayBeOffInSettings:
            Text("May be off in Settings")
        }
    }

    /// The info of the reason: what is wrong and where the fix is, in words.
    var info: Text {
        switch self {
        case .notInApplications:
            Text("macOS shows the items of apps in the Applications folder only. Move the app there and open it again.")
        case .noAppIdentifier:
            Text("This app has no app identifier, so macOS cannot name its item and does not show it. Only its developer can fix this.")
        case .mayBeOffInSettings:
            Text("macOS may have switched this item off. Look for it in System Settings, Menu Bar, and turn it on.")
        }
    }
}

private extension NotShownApps.Fix {
    /// The title of the button.
    var label: Text {
        switch self {
        case .showInFinder:
            Text("Show in Finder")
        case .openMenuBarSettings:
            Text("Open System Settings")
        }
    }
}
