//
//  IslandLiveView.swift
//  holzBar
//

import SwiftUI

extension LiveActivityTint {
    /// The colour in the hub, which is always dark.
    var color: Color {
        switch self {
        case .accent: HolzBarTheme.Palette.accent
        case .amber: HolzBarTheme.Palette.warning
        case .red: HolzBarTheme.Palette.danger
        case .green: HolzBarTheme.Palette.success
        }
    }
}

/// What the island shows while the hub is closed and something is live: the notch widened at menu
/// bar height (concept section 10b, "Live state").
///
/// The top activity's symbol sits left of the camera, tinted by its kind, and its short value
/// sits right of it, with a `+n` badge when more are live; a side that has no free menu bar
/// (``NotchHubGeometry/live(display:room:)``) shows nothing. Both come from ``HubLiveState``, so
/// the view never draws a title, a detail or a name: VoiceOver reads the title. The system draws a
/// countdown itself, so holzBar runs no timer for it. The whole live shape is one button: a click
/// on it asks the hub to open. The view is drawn over the black shape, which the island draws; it
/// adds no surface of its own.
struct IslandLiveView: View {
    /// What the hub says is going on.
    let board: HubActivityBoard.Board
    /// The live shape and the areas of the symbol and the value.
    let layout: NotchHubGeometry.LiveLayout
    /// Where the live shape's top left corner is on the canvas.
    let origin: CGPoint
    /// Called when the shape is clicked.
    let onTap: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                content
            }
            .frame(width: CGFloat(layout.shape.width), height: CGFloat(layout.shape.height), alignment: .topLeading)
            .contentShape(
                IslandShape(
                    topRadius: CGFloat(DesignTokens.Island.liveTopRadius),
                    bottomRadius: CGFloat(DesignTokens.Island.liveBottomRadius)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .offset(x: origin.x, y: origin.y)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let state = HubLiveState.make(board: board, now: .now) {
            // A side whose menu bar is not free does not widen and shows nothing (concept section
            // 10b, "Live state: free span only"): its area is empty.
            if layout.leading.width > 0 {
                Image(systemName: state.symbol)
                    .font(HolzBarTheme.Island.liveSymbolFont)
                    .foregroundStyle(state.tint.color)
                    .accessibilityHidden(true)
                    .frame(width: CGFloat(layout.leading.width), height: CGFloat(layout.shape.height))
                    .offset(x: CGFloat(layout.leading.x - layout.shape.x))
            }
            if layout.trailing.width > 0 {
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    LiveValueText(trailing: state.trailing, font: HolzBarTheme.Island.liveValueFont)
                    if state.extraCount > 0 {
                        badge(state.extraCount)
                    }
                }
                .frame(
                    width: CGFloat(layout.trailing.width),
                    height: CGFloat(layout.shape.height),
                    alignment: .leading
                )
                .offset(x: CGFloat(layout.trailing.x - layout.shape.x))
            }
        }
    }

    private func badge(_ count: Int) -> some View {
        Text(verbatim: "+\(count)")
            .font(HolzBarTheme.Hub.pillFont)
            .monospacedDigit()
            .foregroundStyle(contrast == .increased ? HolzBarTheme.Hub.pillText : HolzBarTheme.Hub.neutral)
            .padding(.horizontal, HolzBarTheme.Spacing.xs)
            .background(HolzBarTheme.Hub.pillFill, in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule().stroke(HolzBarTheme.Hub.neutral)
                }
            }
    }

    // MARK: Accessibility

    /// The title, and how many more are live.
    private var accessibilityText: Text {
        guard let activity = board.compact else {
            return Text("Live activities")
        }
        if board.hiddenCount > 0 {
            return Text("\(activity.title), +\(board.hiddenCount) more")
        }
        return Text(verbatim: activity.title)
    }
}
