//
//  SettingsDisclosure.swift
//  holzBar
//

import SwiftUI

/// A disclosure inside a settings group (D-20): a row with a 10 pt chevron and an accent label
/// that opens more rows below it as sub rows. Its open state lives in the search model, so a
/// found setting inside it can open it before its pane exists; without a model (sheets,
/// previews) the state is local (D-15).
///
/// At most one disclosure per pane is a pane rule (D-13); the kit does not count. A module or
/// rule row's chevron is not a disclosure. The header stays usable while the row is dependent
/// and off (it changes no setting); it dims like a row.
struct SettingsDisclosure<Content: View>: View {
    private let title: Text
    private let id: String
    private let content: Content

    @Environment(SettingsSearchModel.self) private var search: SettingsSearchModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsParentIsOn) private var parentIsOn
    @State private var localIsOpen = false

    init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    private var isOpen: Bool {
        search?.openDisclosures.contains(id) ?? localIsOpen
    }

    private func toggle() {
        withAnimation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion)) {
            if let search {
                if search.openDisclosures.contains(id) {
                    search.openDisclosures.remove(id)
                } else {
                    search.openDisclosures.insert(id)
                }
            } else {
                localIsOpen.toggle()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: HolzBarTheme.SettingsKit.disclosureChevronSize, weight: .semibold))
                        .accessibilityHidden(true)
                    title
                        .font(HolzBarTheme.Typography.body)
                }
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
            .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
            .settingsRowChrome()
            if isOpen {
                content.settingsSubRow()
            }
        }
    }
}
