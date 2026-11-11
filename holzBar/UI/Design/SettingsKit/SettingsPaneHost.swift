//
//  SettingsPaneHost.swift
//  holzBar
//

import SwiftUI

/// The host of one Settings pane (D-15, D-26): a scroll view with the same margins for every
/// pane and the same gap between groups. It draws no ground (the window does) and needs neither
/// the app state nor the search model, so a pane works anywhere a view can go.
struct SettingsPaneHost<Content: View>: View {
    /// The pane this host shows; the reveal of a found setting uses it.
    let pane: SettingsPaneID
    private let content: Content

    init(_ pane: SettingsPaneID, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.groupGap) {
                content
            }
            .padding(.horizontal, HolzBarTheme.SettingsKit.paneMarginHorizontal)
            .padding(.top, HolzBarTheme.SettingsKit.paneMarginTop)
            .padding(.bottom, HolzBarTheme.SettingsKit.paneMarginBottom)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }
}
