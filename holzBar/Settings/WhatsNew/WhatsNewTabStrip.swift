//
//  WhatsNewTabStrip.swift
//  holzBar
//

import SwiftUI

/// The pill tabs of the What's New window: one row of main tabs (major versions) and one of
/// sub tabs (minor versions), oldest on the left.
///
/// The main strip is the window's one glass layer; the sub strip is plain pills on the ground.
/// The installed version's pill carries a small wood dot; VoiceOver hears "Installed" for it,
/// so the state is never colour alone. The Left and Right arrow keys move the selection while
/// the strip has the keyboard.
struct WhatsNewTabStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One tab: an id and the name shown on it, always a version with three numbers.
    struct Tab: Identifiable, Equatable {
        let id: String
        let title: String
    }

    /// The tabs, left to right.
    let tabs: [Tab]
    /// The id of the tab that holds the running app's version, which gets the wood dot; `nil` for none.
    let installed: String?
    /// Whether the strip is a glass capsule; the second strip of the window is not.
    var isGlass = true
    /// The id of the selected tab.
    @Binding var selection: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: HolzBarTheme.Spacing.xs) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        pill(tab, index: index)
                            .id(tab.id)
                    }
                }
                .padding(HolzBarTheme.Spacing.xs)
            }
            // A horizontal scroll view takes all the height it is offered; the strip is one row
            // of pills high, so it takes the height of its content instead.
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, id in
                withAnimation(animation) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .modifier(StripBackground(isGlass: isGlass))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Versions")
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: select(offset: -1)
            case .right: select(offset: 1)
            default: break
            }
        }
    }

    private var animation: Animation {
        HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    private func pill(_ tab: Tab, index: Int) -> some View {
        Chip(verbatim: tab.title, isSelected: tab.id == selection) {
            withAnimation(animation) {
                selection = tab.id
            }
        }
        .overlay(alignment: .topTrailing) {
            if tab.id == installed {
                Circle()
                    .fill(HolzBarTheme.Palette.wood)
                    .frame(width: HolzBarTheme.Spacing.xs, height: HolzBarTheme.Spacing.xs)
                    .padding(HolzBarTheme.Spacing.xxs)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(String(localized: "Version \(tab.title)"))
        .accessibilityValue(spokenValue(tab, index: index))
    }

    /// The position of a tab, followed by "Installed" for the one with the installed version.
    private func spokenValue(_ tab: Tab, index: Int) -> String {
        let position = String(localized: "\(index + 1) of \(tabs.count)")
        guard tab.id == installed else {
            return position
        }
        return ListFormatter.localizedString(byJoining: [position, String(localized: "Installed")])
    }

    /// Moves the selection by the given number of tabs, staying within the strip.
    private func select(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selection }) else {
            return
        }
        let target = index + offset
        guard tabs.indices.contains(target) else {
            return
        }
        withAnimation(animation) {
            selection = tabs[target].id
        }
    }
}

/// The strip's background: the glass capsule of the main strip, nothing for the sub strip.
private struct StripBackground: ViewModifier {
    let isGlass: Bool

    func body(content: Content) -> some View {
        if isGlass {
            content.holzBarGlass(in: Capsule())
        } else {
            content
        }
    }
}

#Preview("WhatsNewTabStrip") {
    @Previewable @State var selection = "1"
    let tabs = [WhatsNewTabStrip.Tab(id: "0", title: "0.0.0"), WhatsNewTabStrip.Tab(id: "1", title: "1.0.0")]
    WhatsNewTabStrip(tabs: tabs, installed: "1", selection: $selection)
        .padding(HolzBarTheme.Spacing.xl)
        .frame(width: 560)
        .background(HolzBarTheme.Palette.ground)
}
