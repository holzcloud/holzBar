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
                    moveButton(for: banner)
                }
            }
            .onAppear {
                LayoutBarItemView.announce(sentence(for: banner))
            }
        }
    }

    private func moveButton(for banner: MakeRoom27.Banner) -> some View {
        Button("Move \(banner.candidates.count) to Hidden") {
            makeRoom.moveCandidates(place: .settings)
        }
        .buttonStyle(.borderedProminent)
        .disabled(banner.candidates.isEmpty)
    }

    /// How many items do not fit.
    private func itemCount(of banner: MakeRoom27.Banner) -> Int {
        switch banner.verdict {
        case let .doesNotFit(items), let .folded(_, items): items
        case .fits, .unknown: 0
        }
    }

    private func sentence(for banner: MakeRoom27.Banner) -> String {
        String(localized: "\(itemCount(of: banner)) items do not fit beside the notch")
    }

    private func info(for banner: MakeRoom27.Banner) -> String {
        [
            String(localized: "These items are wider than the room beside the notch, so macOS folds some away."),
            String(localized: "You can undo it."),
        ].joined(separator: " ")
    }
}
