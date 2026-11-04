//
//  WhatsNewTabStrip.swift
//  holzBar
//

import SwiftUI

/// The pill tabs of the What's New window: one per version, newest on the left.
///
/// The strip is the only glass of the window. The installed version's pill carries a small
/// wood dot; VoiceOver hears "Installed" for it, so the state is never colour alone. The Left
/// and Right arrow keys move the selection while the strip has the keyboard.
struct WhatsNewTabStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The versions, newest first.
    let versions: [String]
    /// The version the running app is, which gets the wood dot; `nil` for none.
    let installed: String?
    /// The selected version.
    @Binding var selection: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: HolzBarTheme.Spacing.xs) {
                    ForEach(Array(versions.enumerated()), id: \.element) { index, version in
                        tab(version, index: index)
                            .id(version)
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
            .onChange(of: selection) { _, version in
                withAnimation(animation) {
                    proxy.scrollTo(version, anchor: .center)
                }
            }
        }
        .holzBarGlass(in: Capsule())
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

    private func tab(_ version: String, index: Int) -> some View {
        Chip(verbatim: version, isSelected: version == selection) {
            withAnimation(animation) {
                selection = version
            }
        }
        .overlay(alignment: .topTrailing) {
            if version == installed {
                Circle()
                    .fill(HolzBarTheme.Palette.wood)
                    .frame(width: HolzBarTheme.Spacing.xs, height: HolzBarTheme.Spacing.xs)
                    .padding(HolzBarTheme.Spacing.xxs)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(String(localized: "Version \(version)"))
        .accessibilityValue(spokenValue(version, index: index))
    }

    /// The position of a version, followed by "Installed" for the installed one.
    private func spokenValue(_ version: String, index: Int) -> String {
        let position = String(localized: "\(index + 1) of \(versions.count)")
        guard version == installed else {
            return position
        }
        return ListFormatter.localizedString(byJoining: [position, String(localized: "Installed")])
    }

    /// Moves the selection by the given number of tabs, staying within the strip.
    private func select(offset: Int) {
        guard let index = versions.firstIndex(of: selection) else {
            return
        }
        let target = index + offset
        guard versions.indices.contains(target) else {
            return
        }
        withAnimation(animation) {
            selection = versions[target]
        }
    }
}

#Preview("WhatsNewTabStrip") {
    @Previewable @State var selection = "1.0.7"
    let versions = (0..<12).map { "1.0.\(11 - $0)" }
    WhatsNewTabStrip(versions: versions, installed: "1.0.7", selection: $selection)
        .padding(HolzBarTheme.Spacing.xl)
        .frame(width: 560)
        .background(HolzBarTheme.Palette.ground)
}
