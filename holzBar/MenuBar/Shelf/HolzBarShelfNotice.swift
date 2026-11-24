//
//  HolzBarShelfNotice.swift
//  holzBar
//

import SwiftUI

/// The notice row under the tiles of the holzBar Shelf (Phase 97, D-08, D-24, concept M2): while
/// the fit model says the bar is full or macOS folded items away, it says so in the Layout
/// pane's words and offers the same one-click move of apps to Hidden, with the undo toast at
/// the menu bar.
///
/// The row is the Shelf's own look: the Shelf's text colour, the Shelf's chip, no accent and no
/// glass. It draws nothing while the apps fit. The row keeps the model running while the Shelf is
/// open and stops it when the Shelf goes, so nothing evaluates while the Shelf is closed.
@available(macOS 27.0, *)
struct HolzBarShelfNotice: View {
    /// The identifier of the chip that moves the apps, for the Shelf's keyboard highlight.
    static let moveChipID = "notice.move"

    let appState: AppState
    /// The tile or chip the keyboard highlights, while the Shelf takes keys.
    var highlightedID: String?

    private var makeRoom: MakeRoom27 {
        appState.makeRoom27
    }

    /// Whether the row is drawn now.
    static func isShown(appState: AppState) -> Bool {
        appState.makeRoom27.shelfBanner?.verdict.isOverflowing == true
    }

    /// The chips the keyboard can reach, in order: the move chip while an app may move.
    static func chipIDs(appState: AppState) -> [String] {
        let makeRoom = appState.makeRoom27
        guard
            let banner = makeRoom.shelfBanner,
            banner.verdict.isOverflowing,
            !banner.candidates.isEmpty,
            !makeRoom.isRunningPass
        else {
            return []
        }
        return [moveChipID]
    }

    /// What a click or the keyboard on a chip does: the same pass as the Layout banner's button.
    static func activate(chipID: String, appState: AppState) {
        guard chipID == moveChipID else {
            return
        }
        appState.makeRoom27.moveCandidates(place: .menuBar)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = makeRoom.shelfBanner, banner.verdict.isOverflowing {
                row(for: banner)
            }
        }
        // The row is always in the tree, so it learns when the Shelf opens and goes even while
        // the apps fit. With "When the menu bar is full" Off the model does not run for the Shelf
        // at all, and the setting applies at once.
        .background {
            Color.clear
                .onAppear {
                    if makeRoom.offersInShelf {
                        makeRoom.surfaceDidOpen(.shelf)
                    }
                }
                .onDisappear {
                    makeRoom.surfaceDidClose(.shelf)
                }
                .onChange(of: makeRoom.offersInShelf) { _, offers in
                    if offers {
                        makeRoom.surfaceDidOpen(.shelf)
                    } else {
                        makeRoom.surfaceDidClose(.shelf)
                    }
                }
        }
    }

    private func row(for banner: MakeRoom27.Banner) -> some View {
        let sentence = makeRoom.sentence(for: banner)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(HolzBarTheme.Palette.stroke)
                .frame(height: HolzBarTheme.Spacing.hairline)
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(HolzBarTheme.Typography.caption)
                    .accessibilityHidden(true)
                Text(sentence)
                    .font(HolzBarTheme.Typography.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: HolzBarTheme.Spacing.xs)
                PreviewBadge()
                    .fixedSize()
                chip(for: banner)
            }
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
            .padding(.vertical, HolzBarTheme.Spacing.xs)
            .frame(
                minWidth: DesignTokens.Comfort.shelfNoticeMinWidth,
                maxWidth: DesignTokens.Comfort.shelfNoticeMaxWidth
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One container after the tiles; the chip inside it is a named button.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(sentence))
    }

    /// The move chip, the busy state while a pass runs, or nothing when no app may move.
    @ViewBuilder
    private func chip(for banner: MakeRoom27.Banner) -> some View {
        if makeRoom.isRunningPass {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Applying…")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        } else if !banner.candidates.isEmpty {
            let isHighlighted = highlightedID == Self.moveChipID
            let appState = appState
            // The Shelf's chip, copied from the fold tile so the two look like siblings.
            Text("Move \(banner.candidates.count) to Hidden")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.18)))
                .padding(.horizontal, 3)
                .frame(minHeight: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
                .overlay {
                    HolzBarShelfClickView(
                        toolTip: makeRoom.info(for: banner),
                        leftClickAction: {
                            Self.activate(chipID: Self.moveChipID, appState: appState)
                        },
                        rightClickAction: nil,
                        drag: nil
                    )
                }
                .keyboardHighlight(isHighlighted)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(isHighlighted ? .isSelected : [])
                .accessibilityLabel(Text("Move \(banner.candidates.count) to Hidden"))
                .accessibilityAction(.default) {
                    Self.activate(chipID: Self.moveChipID, appState: appState)
                }
        }
    }
}
