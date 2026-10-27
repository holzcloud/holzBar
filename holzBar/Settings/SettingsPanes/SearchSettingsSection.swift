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
        HolzBarSection("Search") {
            Toggle("Smart Categories", isOn: $general.smartCategories)
                .annotation("Adds category buttons to the search, such as Network and Media, worked out from what holzBar can read about each app. Nothing is recorded.")
            LabeledContent {
                Button("Forget") {
                    opens.forget()
                }
                .disabled(opens.isEmpty)
            } label: {
                Text("Items you open come first")
            }
            .annotation("The search remembers how often and how lately you open an item from it, so what you use most comes first. A short name such as bt or wlan finds Bluetooth or Wi-Fi. The counts stay on this Mac, are not exported or backed up, and Forget deletes them.")
            .task {
                opens.loadIfNeeded()
            }
        }
    }
}
