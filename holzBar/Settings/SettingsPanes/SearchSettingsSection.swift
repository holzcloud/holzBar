//
//  SearchSettingsSection.swift
//  holzBar
//

import SwiftUI

/// The settings of the search: the category buttons, and what the search remembers of the items
/// opened from it. The memory needs no switch (it is a count per item and day in a small file on
/// this Mac), but it can be forgotten here.
struct SearchSettingsSection: View {
    @Bindable var general: GeneralSettings
    let opens: SearchOpensStore

    var body: some View {
        SettingsGroup(
            SettingsCatalog.LayoutPane.search,
            footnote: Text("A short name such as bt or wlan finds Bluetooth or Wi-Fi.")
        ) {
            SettingsToggleRow(.layoutSmartCategories, isOn: $general.smartCategories)
            SettingsButtonRow(.layoutSearchOpens) {
                Button("Forget") {
                    opens.forget()
                }
                .disabled(opens.isEmpty)
            }
        }
        .task {
            opens.loadIfNeeded()
        }
    }
}
