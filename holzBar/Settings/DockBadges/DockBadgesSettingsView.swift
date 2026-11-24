//
//  DockBadgesSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Dock badges module's settings, in the open area of the module's row: the switch that reads
/// the badge through a private macOS interface (and the line that says when it switched itself
/// off), the one setting for what an item shows while its count is zero, the apps currently in the
/// Dock, in the Dock's order, one switch each, and the lines that say why the list is empty or
/// cannot be read. The list is read only while this view is shown and the module is on, and
/// dropped when it goes.
///
/// The states, in order: with the module off only a line that says to switch it on, and nothing
/// is read; without Accessibility a warning line with the button that asks for it, and an empty
/// list that says so; a Dock that could not be read, a warning line; a Dock without apps, an
/// empty row. The first read draws no spinner: the rows appear when they arrive.
struct DockBadgesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.dockBadges
        let isModuleOn = appState.modules.isEnabled(DockBadges.moduleID)
        let hasAccess = appState.permissions.accessibility.hasPermission
        let dockBadges = appState.dockBadges
        VStack(alignment: .leading, spacing: 0) {
            if isModuleOn {
                SettingsToggleRow(
                    .modulesDockBadgesReadsCounts,
                    isOn: $settings.readsCounts,
                    small: Text("private interface"),
                    badge: .preview
                )
                if settings.readsCounts, dockBadges.countsAreUnavailable {
                    SettingsStateLine(.warning, Text("Badge counts are not available on this Mac"))
                }
                SettingsPickerRow(.modulesDockBadgesZeroMode, selection: $settings.zeroMode) {
                    Text("Dim").tag(DockBadgeZeroMode.dim)
                    Text("Hide").tag(DockBadgeZeroMode.hide)
                }
                if !hasAccess {
                    accessibilityLine
                } else if dockBadges.listState == .unreadable {
                    SettingsStateLine(.warning, Text("The Dock could not be read. Reopen this list to try again."))
                }
                appsHeader
                appsList(hasAccess: hasAccess)
                appsFootnote
            } else {
                SettingsEmptyRow(systemImage: "app.badge", Text("Switch on Dock badges to choose apps."))
            }
        }
        .onAppear {
            dockBadges.settingsDidAppear()
        }
        .onDisappear {
            dockBadges.settingsDidDisappear()
        }
    }

    /// The warning that Accessibility is missing, with the explanation and the button that asks.
    private var accessibilityLine: some View {
        SettingsStateLine(.warning, Text("Accessibility is not granted")) {
            SettingsInfoButton(Text("holzBar reads the badge numbers on the Dock's icons through Accessibility. It reads nothing else and sends nothing anywhere."))
            Button("Grant Accessibility…") {
                appState.permissions.accessibility.performRequest()
            }
        }
    }

    /// The rows of the apps, or the empty row that says why there are none. Before the first read
    /// finishes the list is empty and draws nothing, so a chosen app never shows as gone for a
    /// moment.
    @ViewBuilder
    private func appsList(hasAccess: Bool) -> some View {
        let settings = appState.settings.dockBadges
        let dockBadges = appState.dockBadges
        if !hasAccess {
            SettingsEmptyRow(systemImage: "hand.raised", Text("Grant Accessibility to list the apps in your Dock."))
        } else {
            let rows = dockBadges.listState == .notRead ? [] : dockBadges.rows(chosen: settings.apps)
            if rows.isEmpty, dockBadges.listState == .read {
                SettingsEmptyRow(
                    systemImage: "dock.rectangle",
                    Text("No apps in the Dock. Add an app to the Dock to choose it here.")
                )
            }
            ForEach(rows) { row in
                SettingsToggleRow(
                    Text(verbatim: row.name),
                    icon: Self.icon(forBundleID: row.bundleID),
                    isOn: Binding(
                        get: { settings.isChosen(row.bundleID) },
                        set: { settings.setChosen(row.bundleID, $0) }
                    ),
                    small: row.isChosen && !row.isInDock && dockBadges.listState == .read ? Text("Not in Dock") : nil
                )
                // One line with the tail cut; the whole name is the tooltip and, as the row's
                // label, what VoiceOver reads.
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.name)
            }
        }
    }

    /// The icons already fetched, by bundle identifier, so a row that redraws does not ask the
    /// system again. Dropped by the system under memory pressure.
    private static let icons = NSCache<NSString, NSImage>()

    /// The app's icon for a row, or `nil` when it is not installed.
    private static func icon(forBundleID bundleID: String) -> Image? {
        let key = bundleID as NSString
        // The settings kit hides the icon from VoiceOver; the row's label names the app.
        if let cached = icons.object(forKey: key) {
            // swiftlint:disable:next accessibility_label_for_image
            return Image(nsImage: cached)
        }
        guard let url = BuiltInItemActions.applicationURL(forBundleID: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icons.setObject(image, forKey: key)
        // swiftlint:disable:next accessibility_label_for_image
        return Image(nsImage: image)
    }

    /// The header of the list, laid out as a row of the open area.
    private var appsHeader: some View {
        Text("Apps in the Dock")
            .font(HolzBarTheme.Typography.callout.weight(.semibold))
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome()
    }

    /// What the list holds, under it.
    private var appsFootnote: some View {
        Text("Only apps in the Dock can show a badge.")
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsRowChrome()
    }
}
