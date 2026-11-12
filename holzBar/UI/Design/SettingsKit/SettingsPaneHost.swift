//
//  SettingsPaneHost.swift
//  holzBar
//

import SwiftUI

/// The host of one Settings pane (D-15, D-26): a scroll view with the same margins for every
/// pane and the same gap between groups. It draws no ground (the window does). It works without
/// the app state and without the search model; with the model in the environment it also leads a
/// found setting into view (D-25): it scrolls to the row the model names and highlights it for a
/// moment.
struct SettingsPaneHost<Content: View>: View {
    /// How long the highlight of a revealed row stays at full strength, in seconds.
    private static var highlightHold: Double { 1 }

    /// How long the highlight of a revealed row takes to fade out, in seconds.
    private static var highlightFade: Double { 1 }

    /// The pane this host shows.
    let pane: SettingsPaneID
    private let content: Content

    @Environment(SettingsSearchModel.self) private var search: SettingsSearchModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ pane: SettingsPaneID, @ViewBuilder content: () -> Content) {
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
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
            // Only one pane host is on screen at a time and a reveal switches the pane in the same
            // main-actor turn as it sets the target, so the host that sees the target is the
            // host of the target's pane. A target that no row carries scrolls nowhere and fades.
            .onChange(of: search?.revealTarget, initial: true) { _, target in
                guard let search, let target else { return }
                search.revealTarget = nil
                reveal(target, in: search, proxy: proxy)
            }
        }
    }

    /// Scrolls to the row and fades its highlight in, then out. It waits one main-actor turn, so
    /// a pane or a disclosure that opened in the same step is laid out first. No timer runs: the
    /// fade-out starts from the completion of the first animation and carries its own delay.
    private func reveal(_ target: String, in search: SettingsSearchModel, proxy: ScrollViewProxy) {
        let reduceMotion = reduceMotion
        Task {
            withAnimation(
                HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
                completionCriteria: .logicallyComplete
            ) {
                proxy.scrollTo(target, anchor: .center)
                search.highlightedEntry = target
            } completion: {
                // The hold stays with Reduce Motion; only the fade gets shorter.
                let fade = HolzBarTheme.Motion.resolved(
                    .easeOut(duration: Self.highlightFade),
                    reduceMotion: reduceMotion
                )
                withAnimation(fade.delay(Self.highlightHold)) {
                    search.highlightedEntry = nil
                }
            }
        }
    }
}
