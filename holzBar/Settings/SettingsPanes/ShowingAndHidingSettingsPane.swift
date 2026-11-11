//
//  ShowingAndHidingSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The Showing & Hiding pane of the Settings window.
struct ShowingAndHidingSettingsPane: View {
    @Environment(AppState.self) private var appState
    /// Changes when the displays do, so the list of displays is read again.
    @State private var displayListVersion = 0

    var body: some View {
        @Bindable var general = appState.settings.general
        @Bindable var advanced = appState.settings.advanced

        SettingsPaneHost(.showingAndHiding) {
            SettingsGroup(SettingsCatalog.ShowingAndHidingPane.showHiddenItems) {
                SettingsToggleRow(.hidingShowOnClick, isOn: $general.showOnClick)
                SettingsToggleRow(.hidingShowOnHover, isOn: $general.showOnHover)
                SettingsSliderRow(
                    .hidingHoverDelay,
                    value: $advanced.showOnHoverDelay,
                    in: 0...1,
                    step: 0.1,
                    valueLabel: seconds
                )
                .settingsSubRow()
                .settingsDependent(on: general.showOnHover)
                SettingsToggleRow(.hidingShowOnScroll, isOn: $general.showOnScroll)
                SettingsToggleRow(.hidingOpenInMenuBar, isOn: $advanced.openHiddenItemsInMenuBar)
            }
            hideAgainGroup(general: general, advanced: advanced)
            displaysGroup(general: general)
            animationGroup(general: general)
        }
        .task {
            // A display that connects or leaves changes the rows of the displays.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                displayListVersion += 1
            }
        }
    }

    // MARK: Hide again

    @ViewBuilder
    private func hideAgainGroup(general: GeneralSettings, advanced: AdvancedSettings) -> some View {
        @Bindable var general = general
        @Bindable var advanced = advanced
        SettingsGroup(SettingsCatalog.ShowingAndHidingPane.hideAgain) {
            SettingsToggleRow(.hidingAutoRehide, isOn: $general.autoRehide)
            SettingsPickerRow(
                .hidingRehideStrategy,
                selection: $general.rehideStrategy,
                info: rehideStrategyInfo(general.rehideStrategy)
            ) {
                ForEach(RehideStrategy.allCases) { strategy in
                    Text(strategy.localized).tag(strategy)
                }
            }
            .settingsSubRow()
            .settingsDependent(on: general.autoRehide)
            SettingsSliderRow(
                .hidingRehideInterval,
                value: rehideIntervalKnob(general),
                in: 1...30,
                step: 1,
                small: Text("fixed time only"),
                valueLabel: { _ in seconds(general.rehideInterval) }
            )
            .settingsSubRow()
            .settingsDependent(on: general.autoRehide && general.rehideStrategy == .timed)
            SettingsSliderRow(
                .hidingTempShowInterval,
                value: $advanced.tempShowInterval,
                in: 0...30,
                step: 1,
                valueLabel: seconds
            )
        }
    }

    /// The knob of Time until hiding: the stored value raised to at least 1, so a stored 0 stays
    /// 0 (and reads 0s) until the user moves the slider.
    private func rehideIntervalKnob(_ general: GeneralSettings) -> Binding<Double> {
        Binding {
            max(general.rehideInterval, 1)
        } set: { newValue in
            general.rehideInterval = newValue
        }
    }

    /// What the chosen option of When to hide again does.
    private func rehideStrategyInfo(_ strategy: RehideStrategy) -> Text {
        switch strategy {
        case .smart:
            Text("Hidden items hide again as soon as you click a window or the Dock, outside the menu bar.")
        case .timed:
            Text("Hidden items hide again once the pointer has been out of the menu bar for the time you set.")
        case .focusedApp:
            Text("Hidden items hide again as soon as another app comes to the front.")
        }
    }

    // MARK: Displays

    /// The connected displays, by name.
    private struct ConnectedDisplay: Identifiable {
        let uuid: String
        let name: String
        var id: String { uuid }
    }

    private var connectedDisplays: [ConnectedDisplay] {
        _ = displayListVersion
        return NSScreen.screens.compactMap { screen in
            Bridging.getDisplayUUIDString(for: screen.displayID).map {
                ConnectedDisplay(uuid: $0, name: screen.localizedName)
            }
        }
    }

    /// The choice for one display.
    private func displayBehavior(for uuid: String, in general: GeneralSettings) -> Binding<DisplayBehavior> {
        Binding {
            general.displayBehaviors.behavior(of: uuid)
        } set: { behavior in
            var behaviors = general.displayBehaviors
            behaviors.set(behavior, for: uuid)
            general.displayBehaviors = behaviors
        }
    }

    /// One row per connected display, shown when there is more than one or a choice is stored
    /// (D-70). The rows are text rows: a display's name is user data and stays out of the search.
    @ViewBuilder
    private func displaysGroup(general: GeneralSettings) -> some View {
        let displays = connectedDisplays
        if displays.count > 1 || !general.displayBehaviors.isEmpty {
            SettingsGroup(
                SettingsCatalog.ShowingAndHidingPane.displays,
                footnote: Text("The display under the pointer decides.")
            ) {
                ForEach(displays) { display in
                    SettingsPickerRow(
                        Text(verbatim: display.name),
                        selection: displayBehavior(for: display.uuid, in: general),
                        info: Text(verbatim: SettingsEntry.hidingDisplays.info ?? "")
                    ) {
                        ForEach(DisplayBehavior.allCases) { behavior in
                            Text(behavior.localized).tag(behavior)
                        }
                    }
                }
            }
            .id(SettingsEntry.hidingDisplays.id)
        }
    }

    // MARK: Animation

    @ViewBuilder
    private func animationGroup(general: GeneralSettings) -> some View {
        @Bindable var general = general
        SettingsGroup(SettingsCatalog.ShowingAndHidingPane.animation) {
            SettingsPictureCardRow(
                .hidingAnimationStyle,
                selection: $general.revealAnimationStyle,
                values: RevealAnimationStyle.allCases,
                info: animationInfo,
                name: { Text($0.localized) },
                picture: { AnimationStylePicture(style: $0) }
            )
        }
    }

    /// One explanation for the running macOS: what moves depends on the backend.
    private var animationInfo: Text {
        switch MenuBarBackendKind.current {
        case .service26:
            Text("Smooth slides the menu bar's items and the holzBar Shelf in and out. Fade fades the holzBar Shelf in while the items change at once. Nothing moves while Reduce Motion is on.")
        case .accessibility27:
            Text("On macOS 27, macOS animates the menu bar itself, so the style applies to the holzBar Shelf: Smooth slides it out, Fade fades it in. Nothing moves while Reduce Motion is on.")
        case .windowList:
            Text("On this version of macOS the menu bar's items change at once, so the style applies to the holzBar Shelf: Smooth slides it out, Fade fades it in. Nothing moves while Reduce Motion is on.")
        }
    }

    // MARK: Values

    /// The value of a seconds slider, as the system writes it in the user's language.
    private func seconds(_ value: Double) -> Text {
        Text(
            Measurement(value: value, unit: UnitDuration.seconds),
            format: .measurement(
                width: .narrow,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...1))
            )
        )
    }
}

// MARK: - DisplayBehavior

extension DisplayBehavior {
    /// The name of the behaviour.
    var localized: LocalizedStringKey {
        switch self {
        case .standard: "Default"
        case .showEverything: "Always show everything"
        case .collapse: "Collapse"
        }
    }
}
