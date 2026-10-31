//
//  AppleItemsSection.swift
//  holzBar
//

import SwiftUI

/// The settings of the Apple Items module (macOS 27): which of Apple's system items to hide.
/// The Modules pane shows it under the module's row while the module is on.
struct AppleItemsSection: View {
    var appleItems: AppleItems

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle(isOn: binding(for: .clock)) {
                HStack(spacing: HolzBarTheme.Spacing.sm) {
                    Text("Hide the clock")
                    PreviewBadge()
                }
            }
            Toggle("Hide Control Center", isOn: binding(for: .controlCentre))
            Toggle("Hide Wi-Fi", isOn: binding(for: .wifi))
            Toggle("Hide the battery", isOn: binding(for: .battery))
            caption(Text("While a system item is hidden, Control Center does not show its camera and microphone indicator; holzBar marks its own icon instead."))
            replacementsList
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    private var replacementsList: some View {
        let candidates = appleItems.candidates()
        let isFull = appleItems.replacements.count >= AppleItemReplacement.maximumCount
        return VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Text("Replacement items")
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityAddTraits(.isHeader)
            caption(Text("Hide an Apple app's items in Menu Bar Layout, and keep the ones you want one click away here."))
            ForEach(appleItems.replacements) { replacement in
                row(for: replacement)
            }
            addMenu(candidates: candidates, isFull: isFull)
            if isFull {
                caption(Text("Six replacement items are the most."))
            } else if candidates.isEmpty {
                caption(Text("No Apple items on the bar to replace."))
            }
        }
        .padding(.top, HolzBarTheme.Spacing.sm)
    }

    private func row(for replacement: AppleItemReplacement) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
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
            Text(verbatim: replacement.title)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.text)
            Spacer(minLength: HolzBarTheme.Spacing.sm)
            Button("Remove") {
                appleItems.removeReplacement(id: replacement.id)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove \(replacement.title)"))
        }
        .accessibilityElement(children: .contain)
    }

    private func addMenu(candidates: [(key: String, title: String)], isFull: Bool) -> some View {
        Menu("Add Replacement…") {
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
