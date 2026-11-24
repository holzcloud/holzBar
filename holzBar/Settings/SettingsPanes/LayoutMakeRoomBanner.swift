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

    var body: some View {
        if let banner = makeRoom.banner, banner.verdict.isOverflowing {
            SettingsGroup {
                SettingsStateLine(.warning, Text(sentence(for: banner))) {
                    PreviewBadge()
                    SettingsInfoButton(Text(info(for: banner)))
                    action(for: banner)
                }
                if makeRoom.failedCount > 0 {
                    SettingsStateLine(.warning, Text("Could not be moved: \(makeRoom.failedCount)"))
                }
            }
            .onAppear {
                LayoutBarItemView.announce(sentence(for: banner))
            }
        }
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

    /// How many items do not fit.
    private func itemCount(of banner: MakeRoom27.Banner) -> Int {
        switch banner.verdict {
        case let .doesNotFit(items), let .folded(_, items): items
        case .fits, .unknown: 0
        }
    }

    private func sentence(for banner: MakeRoom27.Banner) -> String {
        let items = itemCount(of: banner)
        return banner.hasNotch
            ? String(localized: "\(items) items do not fit beside the notch")
            : String(localized: "\(items) items do not fit in the menu bar")
    }

    /// What the info button says: why the bar is full, what a move can do, that it can be undone
    /// and which apps the button would move. No sentence promises that a move gives more
    /// space: that is measured on a Mac first. Without a candidate the info says why nothing can move.
    private func info(for banner: MakeRoom27.Banner) -> String {
        guard !banner.candidates.isEmpty else {
            return String(localized: "Nothing can move: the rest are Apple's items, holzBar's own or protected. Quit an app or remove an item to make room.")
        }
        let why = banner.hasNotch
            ? String(localized: "These items are wider than the room beside the notch, so macOS folds some away.")
            : String(localized: "These items are wider than the room in the menu bar, so macOS folds some away.")
        // The names are the apps' own, shown as they are; they never reach a log line.
        let names = ListFormatter.localizedString(byJoining: banner.candidates.map(\.name))
        return [why, canMakeRoom(for: banner), String(localized: "You can undo it."), names].joined(separator: " ")
    }

    /// The apps you use least while Usage suggestions is on, some apps otherwise (D-17).
    private func canMakeRoom(for banner: MakeRoom27.Banner) -> String {
        banner.usesUsage
            ? String(localized: "Moving the apps you use least to Hidden can make room.")
            : String(localized: "Moving some apps to Hidden can make room.")
    }
}
