//
//  AppleItemsSection.swift
//  holzBar
//

import SwiftUI

/// The settings of the Apple Items module (macOS 27) as kit rows, shown in the open area of the
/// module's row: which of Apple's system items to hide, and the replacement items.
struct AppleItemsSection: View {
    var appleItems: AppleItems

    var body: some View {
        let candidates = appleItems.candidates()
        let isFull = appleItems.replacements.count >= AppleItemReplacement.maximumCount
        SettingsToggleRow(.modulesAppleItemsHideClock, isOn: binding(for: .clock))
        SettingsToggleRow(.modulesAppleItemsHideControlCenter, isOn: binding(for: .controlCentre))
        SettingsToggleRow(.modulesAppleItemsHideWiFi, isOn: binding(for: .wifi))
        SettingsToggleRow(.modulesAppleItemsHideBattery, isOn: binding(for: .battery))
        SettingsButtonRow(
            .modulesAppleItemsReplacements,
            small: appleItems.replacements.isEmpty ? Text("none yet") : nil
        ) {
            addMenu(candidates: candidates, isFull: isFull)
        }
        ForEach(appleItems.replacements) { replacement in
            row(for: replacement)
                .settingsSubRow()
        }
        if isFull {
            SettingsStateLine(.info, Text("Six replacement items are the most."))
        } else if candidates.isEmpty {
            SettingsStateLine(.info, Text("No Apple items on the bar to replace."))
        }
    }

    private func row(for replacement: AppleItemReplacement) -> some View {
        SettingsRow(Text(verbatim: replacement.title)) {
            Picker("Symbol", selection: symbolBinding(for: replacement)) {
                ForEach(AppleItemCatalog.symbolNames, id: \.self) { name in
                    Image(systemName: name)
                        .tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(Text("Symbol"))
            .fixedSize()
            Button("Delete") {
                appleItems.removeReplacement(id: replacement.id)
            }
            .accessibilityLabel(Text("Delete \(replacement.title)"))
        }
    }

    private func addMenu(candidates: [(key: String, title: String)], isFull: Bool) -> some View {
        Menu("Add…") {
            ForEach(candidates, id: \.key) { candidate in
                Button(candidate.title) {
                    appleItems.addReplacement(forItemKey: candidate.key, title: candidate.title)
                }
            }
        }
        .fixedSize()
        .disabled(candidates.isEmpty || isFull)
    }

    private func symbolBinding(for replacement: AppleItemReplacement) -> Binding<String> {
        Binding(
            get: { replacement.symbolName },
            set: { appleItems.setSymbol($0, for: replacement.id) }
        )
    }

    private func binding(for item: SystemItem27) -> Binding<Bool> {
        Binding(
            get: { appleItems.isHidden(item) },
            set: { appleItems.setHidden(item, $0) }
        )
    }
}
