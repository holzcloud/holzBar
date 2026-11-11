//
//  GeneralSettingsPane.swift
//  holzBar
//

import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var settings: GeneralSettings
    @State private var isApplyingItemSpacingOffset = false
    @State private var tempItemSpacingOffset: CGFloat = 0

    private var itemSpacingOffsetKey: LocalizedStringKey {
        switch tempItemSpacingOffset {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: "\(tempItemSpacingOffset.formatted())"
        }
    }

    var body: some View {
        HolzBarForm {
            HolzBarSection("Startup") {
                appOptions
            }
            HolzBarSection("Menu Bar Icon") {
                holzBarIconOptions
            }
            HolzBarSection("holzBar Shelf") {
                shelfOptions
            }
            if #available(macOS 27.0, *) {
                HolzBarSection("Showing Items") {
                    clockOpensNotificationCenter
                }
            }
            HolzBarSection("Item Spacing") {
                spacingOptions
            }
            if #available(macOS 27.0, *) {
                PrivacyIndicatorNote(settings: settings)
            }
        }
    }

    // MARK: App Options

    @ViewBuilder
    private var appOptions: some View {
        LaunchAtLoginToggle()
        Toggle("Show What's New after an update", isOn: $settings.showsWhatsNewAfterUpdate)
            .annotation("The What's New window opens once after holzBar is updated.")
    }

    // MARK: holzBar Icon Options

    @ViewBuilder
    private var holzBarIconOptions: some View {
        HolzBarIconCards(settings: settings)
        if settings.showHolzBarIcon {
            Toggle(isOn: $settings.showsHiddenItemCount) {
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Text("Show the number of hidden items on the icon")
                }
            }
            .annotation("A small number on the holzBar icon says how many items are hidden right now.")
        }
    }

    // MARK: holzBar Shelf Options

    @ViewBuilder
    private var shelfOptions: some View {
        useShelf
        if settings.useShelf {
            shelfStylePicker
            shelfLocationPicker
            shelfLayoutPicker
            shelfFindsByTyping
            shelfFoldPicker
            shelfShowsClosedApps
            shelfDragsTiles
            shelfDisplaysPicker
            if #available(macOS 27.0, *) {
                Toggle("Show items covered by the notch", isOn: $settings.showsNotchOverflowInShelf)
                    .annotation {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visible items that the notch hides, for example behind a long application menu, also appear in the holzBar Shelf.")
                            Text("On macOS 27, items that macOS shows in its own expanded overflow are not listed a second time.")
                        }
                    }
            } else {
                Toggle("Show items covered by the notch", isOn: $settings.showsNotchOverflowInShelf)
                    .annotation("Visible items that the notch hides, for example behind a long application menu, also appear in the holzBar Shelf.")
            }
        }
    }

    @ViewBuilder
    private var useShelf: some View {
        Toggle("Use holzBar Shelf", isOn: $settings.useShelf)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
    }

    @ViewBuilder
    private var shelfLayoutPicker: some View {
        PictureCardRow(
            selection: $settings.shelfLayout,
            values: ShelfLayout.allCases,
            name: \.localized
        ) {
            Text("Layout")
        } picture: { layout in
            ShelfLayoutPicture(layout: layout)
        }
        .annotation("A row holds every item side by side. A grid and a column hold more items without scrolling.")
    }

    @ViewBuilder
    private var shelfFindsByTyping: some View {
        Toggle(isOn: $settings.shelfFindsByTyping) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Find items by typing")
            }
        }
        .annotation("Type in the holzBar Shelf to highlight the best match. Return opens its menu and Escape closes the holzBar Shelf. The holzBar Shelf takes the keyboard when a hotkey opens it.")
    }

    @ViewBuilder
    private var shelfFoldPicker: some View {
        if appState.settings.advanced.enableAlwaysHiddenSection {
            HolzBarPicker(selection: $settings.shelfAlwaysHiddenFold) {
                Text("Folded each time").tag(ShelfAlwaysHiddenFold.foldedEachTime)
                Text("As I left them").tag(ShelfAlwaysHiddenFold.remembered)
            } label: {
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Text("Always-hidden items")
                }
            }
            .annotation("The holzBar Shelf shows the always-hidden items behind one tile. Click the tile to open them.")
        }
    }

    @ViewBuilder
    private var shelfShowsClosedApps: some View {
        Toggle(isOn: $settings.shelfShowsClosedApps) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Show applications that are not running")
            }
        }
        .annotation("Applications with a hidden item that are closed appear dimmed in the holzBar Shelf. Click one to open it.")
    }

    @ViewBuilder
    private var shelfDragsTiles: some View {
        Toggle(isOn: $settings.shelfDragsTiles) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Rearrange items by dragging")
            }
        }
        .annotation("Drag an item in the holzBar Shelf to put it in order, into another section or up onto the menu bar to show it there. Where macOS puts the items of a section in order itself, an item can only change its section.")
    }

    @ViewBuilder
    private var shelfStylePicker: some View {
        PictureCardRow(
            selection: $settings.shelfStyle,
            values: HolzBarShelfStyle.allCases,
            name: \.localized
        ) {
            Text("Style")
        } picture: { style in
            ShelfStylePicture(style: style)
        }
        .annotation {
            switch settings.shelfStyle {
            case .attached:
                Text("The holzBar Shelf hangs directly below the menu bar.")
            case .floating:
                Text("The holzBar Shelf floats a little below the menu bar, as a bar of its own.")
            }
        }
    }

    @ViewBuilder
    private var shelfLocationPicker: some View {
        HolzBarPicker("Location", selection: $settings.shelfLocation) {
            ForEach(HolzBarShelfLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        }
        .annotation {
            switch settings.shelfLocation {
            case .dynamic:
                Text("The holzBar Shelf's location changes based on context.")
            case .mousePointer:
                Text("The holzBar Shelf is centered below the mouse pointer.")
            case .holzBarIcon:
                Text("The holzBar Shelf is centered below the holzBar icon.")
            case .screenEdge:
                Text("The holzBar Shelf is at the right edge of the screen.")
            }
        }
    }

    @ViewBuilder
    private var shelfDisplaysPicker: some View {
        HolzBarPicker("Use on", selection: $settings.shelfDisplays) {
            ForEach(HolzBarShelfDisplays.allCases) { displays in
                Text(displays.localized).tag(displays)
            }
        }
        .annotation("On other displays, hidden menu bar items are shown in the menu bar itself.")
    }

    // MARK: Clock

    @ViewBuilder
    private var clockOpensNotificationCenter: some View {
        if #available(macOS 27.0, *) {
            Toggle(isOn: $settings.clockOpensNotificationCenter) {
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Text("Open Notification Center from the clock")
                }
            }
            .annotation("While items are hidden, macOS 27 ignores a click on the clock. holzBar lifts the hiding for a moment and clicks again, so Notification Center opens. Turn this off to leave the click to macOS; the clock then does nothing while items are hidden. It needs only the Accessibility permission holzBar has already.")
        }
    }

    // MARK: Spacing Options

    @ViewBuilder
    private var spacingOptions: some View {
        LabeledContent {
            HolzBarSlider(
                itemSpacingOffsetKey,
                value: $tempItemSpacingOffset,
                in: -16...16,
                step: 2
            )
            .disabled(isApplyingItemSpacingOffset)
        } label: {
            LabeledContent {
                Button("Apply") {
                    applyTempItemSpacingOffset()
                }
                .help("Apply the current spacing")
                .disabled(isApplyingItemSpacingOffset || tempItemSpacingOffset == settings.itemSpacingOffset)

                if isApplyingItemSpacingOffset {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Button {
                        tempItemSpacingOffset = 0
                        applyTempItemSpacingOffset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to the default spacing")
                    .accessibilityLabel("Reset to the default spacing")
                    .disabled(isApplyingItemSpacingOffset || settings.itemSpacingOffset == 0)
                }
            } label: {
                HStack {
                    Text("Menu bar item spacing")
                    BetaBadge()
                }
            }
        }
        .annotation(
            "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.",
            spacing: 2
        )
        .annotation(spacing: 10) {
            CalloutBox(
                "Note: You may need to log out and back in for this setting to apply properly.",
                systemImage: "exclamationmark.circle"
            )
        }
        .onAppear {
            tempItemSpacingOffset = settings.itemSpacingOffset
        }
    }

    private func applyTempItemSpacingOffset() {
        isApplyingItemSpacingOffset = true
        settings.itemSpacingOffset = tempItemSpacingOffset
        Task {
            // The spinner stops before the alert: the alert waits for the user, who may not
            // see it while another app is active.
            await SpacingRelaunch.apply {
                try await appState.spacingManager.applyOffset()
            } finished: {
                isApplyingItemSpacingOffset = false
            } reportFailure: { error in
                await NSAlert(error: error).present(attachedTo: appState.navigationState.settingsWindow)
            }
        }
    }
}

// MARK: - PrivacyIndicatorNote

/// Tells the user that macOS 27 hides Control Centre's privacy indicator while holzBar
/// hides items.
///
/// On macOS 27 holzBar hides applications' items with a menu bar assessment assertion
/// (`MenuBarAssessmentAssertion27`). While one is live, MenuBarAgent no longer draws Control
/// Centre's capture indicator (green for the camera, orange for the microphone, indigo for
/// screen sharing or recording), whatever the assertion keeps; only the small green dot
/// beside the clock stays. Measured on macOS 27.0; holzBar cannot keep the indicator, so it
/// says so and offers a dot on its own icon instead, for the microphone and the camera
/// (there is no public signal for screen recording).
@available(macOS 27.0, *)
private struct PrivacyIndicatorNote: View {
    @Bindable var settings: GeneralSettings

    var body: some View {
        HolzBarSection {
            VStack(alignment: .leading, spacing: 3) {
                Label("The camera and microphone indicator is hidden", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("On macOS 27, while holzBar hides menu bar items, Control Centre does not show its indicator for the camera, the microphone or screen recording. It comes back while holzBar hides no item. holzBar can mark its own icon instead, for the microphone and the camera but not for screen recording. The small green dot beside the clock still appears while the camera is on.")
                    .font(HolzBarTheme.Typography.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Show a dot on the holzBar icon while the microphone or camera is in use", isOn: $settings.holzBarIconShowsCaptureDot)
                .annotation("Orange for the microphone, green for the camera. Uses no permission; holzBar cannot tell when an app records the screen.")
        }
    }
}
