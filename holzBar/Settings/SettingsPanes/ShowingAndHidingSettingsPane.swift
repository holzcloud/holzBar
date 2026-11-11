//
//  ShowingAndHidingSettingsPane.swift
//  holzBar
//

import SwiftUI

/// The Showing & Hiding pane of the Settings window.
struct ShowingAndHidingSettingsPane: View {
    @Environment(AppState.self) private var appState

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
        }
    }

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
