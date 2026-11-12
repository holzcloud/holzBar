//
//  AboutSettingsPane.swift
//  holzBar
//

import SwiftUI

/// About holzBar on the settings kit: a header with the icon, the name and the license, the
/// links and the credit to Ice, one row for updating, and the rest (What's New, the
/// acknowledgements, diagnostics, Quit).
///
/// holzBar never looks for updates: the Updating row shows the Homebrew commands for the user to
/// copy and opens the release notes in the browser, the only way holzBar reaches the network.
struct AboutSettingsPane: View {
    @Environment(AppState.self) var appState
    @Environment(\.openURL) private var openURL
    @State private var isShowingAcknowledgements = false
    @State private var isShowingDiagnostics = false

    var body: some View {
        SettingsPaneHost(.about) {
            header
            SettingsGroup {
                SettingsValueRow(.aboutVersion, value: Text(verbatim: Constants.versionString))
                    .textSelection(.enabled)
                SettingsButtonRow(.aboutWebsite) {
                    Button {
                        openURL(Constants.websiteURL)
                    } label: {
                        Text(verbatim: websiteAddress)
                    }
                }
                SettingsButtonRow(.aboutRepository) {
                    Button("Contribute") {
                        openURL(Constants.repositoryURL)
                    }
                }
                SettingsButtonRow(.aboutReportBug) {
                    Button("Open Issues") {
                        openURL(Constants.issuesURL)
                    }
                }
                SettingsButtonRow(.aboutBasedOnIce) {
                    Button("Open Ice") {
                        openURL(Constants.originalIceURL)
                    }
                }
            }
            SettingsGroup(SettingsCatalog.AboutPane.updating) {
                updatingRow
            }
            SettingsGroup(SettingsCatalog.AboutPane.more) {
                SettingsButtonRow(.aboutWhatsNew) {
                    Button("What's New…") {
                        appState.activate(for: .whatsNew)
                        appState.openWindow(.whatsNew)
                    }
                }
                SettingsButtonRow(.aboutAcknowledgements) {
                    Button("Show") {
                        isShowingAcknowledgements = true
                    }
                }
                SettingsButtonRow(.aboutDiagnostics) {
                    Button("Copy Diagnostics…") {
                        isShowingDiagnostics = true
                    }
                }
                SettingsButtonRow(.aboutQuit) {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsSheet()
        }
    }

    /// The icon, the name, the license and the copyright notice (GPL-3.0 asks an interactive
    /// program to show its legal notices).
    private var header: some View {
        HStack(spacing: HolzBarTheme.Spacing.md) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: HolzBarTheme.Spacing.huge, height: HolzBarTheme.Spacing.huge)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text(verbatim: "holzBar")
                    .font(HolzBarTheme.Typography.headline)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                Text("Free software under the GPL-3.0")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                Text(Constants.copyrightString)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The website's address without the scheme, as the button shows it.
    private var websiteAddress: String {
        (Constants.websiteURL.host() ?? "") + Constants.websiteURL.path()
    }

    /// The one row of the Updating group: both Homebrew commands as selectable text, in the
    /// order the running version suggests, and the button that opens the release notes.
    private var updatingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.labelControlGap) {
            HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                    ForEach(AboutUpdateCommands.commands(forVersion: Constants.versionString), id: \.text) { command in
                        Text(verbatim: command.text)
                            .font(HolzBarTheme.Typography.mono)
                            .foregroundStyle(HolzBarTheme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Update commands"))
                if let info = SettingsEntry.aboutHowToUpdate.info {
                    SettingsInfoButton(Text(info))
                }
            }
            Spacer(minLength: 0)
            Button("How to Update holzBar…") {
                openURL(Constants.releasesURL)
            }
        }
        .settingsRowChrome(entryID: SettingsEntry.aboutHowToUpdate.id)
        .accessibilityElement(children: .contain)
    }
}
