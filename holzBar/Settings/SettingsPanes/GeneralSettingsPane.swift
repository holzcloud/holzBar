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
