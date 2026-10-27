//
//  AppleItemsSection.swift
//  holzBar
//

import SwiftUI

/// The settings of the Apple Items module (macOS 27): which of Apple's system items to hide.
/// The Modules pane shows it under the module's row while the module is on.
struct AppleItemsSection: View {
    @Environment(AppState.self) private var appState
    var appleItems: AppleItems

    private var shelfIsOn: Bool {
        appState.settings.general.useShelf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Hide the clock", isOn: binding(for: .clock))
            Toggle("Hide Control Center", isOn: binding(for: .controlCentre))
            Toggle("Hide Wi-Fi", isOn: binding(for: .wifi))
            Toggle("Hide the battery", isOn: binding(for: .battery))
            if shelfIsOn {
                caption(Text("Not applied while the holzBar Shelf is on: the Shelf cannot show a system item."))
            }
            caption(Text("While a system item is hidden, Control Center does not show its camera and microphone indicator; holzBar marks its own icon instead."))
            replacementsList
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    private var replacementsList: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Text("Replacement items")
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(appleItems.replacements) { replacement in
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Image(systemName: replacement.symbolName)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .frame(width: HolzBarTheme.Spacing.xl)
                        .accessibilityHidden(true)
                    Text(verbatim: replacement.title)
                        .font(HolzBarTheme.Typography.body)
                        .foregroundStyle(HolzBarTheme.Palette.text)
                    Spacer(minLength: HolzBarTheme.Spacing.sm)
                    Button("Remove") {
                        appleItems.removeReplacement(id: replacement.id)
                    }
                    .buttonStyle(.borderless)
                }
            }
            addMenu
        }
        .padding(.top, HolzBarTheme.Spacing.sm)
    }

    private var addMenu: some View {
        let candidates = appleItems.candidates()
        return Menu("Add Replacement…") {
            ForEach(candidates, id: \.key) { candidate in
                Button(candidate.title) {
                    appleItems.addReplacement(forItemKey: candidate.key, title: candidate.title)
                }
            }
        }
        .fixedSize()
        .disabled(candidates.isEmpty || appleItems.replacements.count >= AppleItemReplacement.maximumCount)
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(for item: SystemItem27) -> Binding<Bool> {
        Binding(
            get: { appleItems.isHidden(item) },
            set: { appleItems.setHidden(item, $0) }
        )
    }
}
