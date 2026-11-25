//
//  LayoutMakeRoomBanner.swift
//  holzBar
//

import SwiftUI

/// The fit warning at the top of Layout (Phase 97, D-07, D-11): the apps in the Visible section
/// are wider than the room, with one button that moves the apps holzBar may move to Hidden.
///
/// One group without a header holding one state line: the warning triangle, the sentence, the
/// Preview badge, an info button and one prominent button. It shows only while the model says
/// the bar is full, and it needs no switch because `MakeRoom27` runs only while Layout is open.
@available(macOS 27.0, *)
struct MakeRoomBanner: View {
    let makeRoom: MakeRoom27

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The group appears and leaves with a fade; the model already waited out the settle time,
        // so nothing flickers. Reduce Motion shortens the fade.
        Group {
            if let banner = makeRoom.banner, banner.verdict.isOverflowing {
                SettingsGroup {
                    SettingsStateLine(.warning, Text(makeRoom.sentence(for: banner))) {
                        PreviewBadge()
                        SettingsInfoButton(Text(makeRoom.info(for: banner)))
                        action(for: banner)
                    }
                    if makeRoom.failedCount > 0 {
                        SettingsStateLine(.warning, Text("Could not be moved: \(makeRoom.failedCount)"))
                    }
                }
                .transition(.opacity)
                .onAppear {
                    // Once, when the banner appears while Layout is open; leaving is not announced.
                    LayoutBarItemView.announce(makeRoom.sentence(for: banner))
                }
            }
        }
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
            value: makeRoom.banner != nil
        )
    }

    /// The button, the busy state while a pass runs, or nothing when no app may move.
    @ViewBuilder
    private func action(for banner: MakeRoom27.Banner) -> some View {
        if makeRoom.isRunningPass {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Applying…")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if !banner.candidates.isEmpty {
            Button("Move \(banner.candidates.count) to Hidden") {
                makeRoom.moveCandidates(place: .settings)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
