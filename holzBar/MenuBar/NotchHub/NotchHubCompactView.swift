//
//  NotchHubCompactView.swift
//  holzBar
//

import AppKit
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

/// The shape of the compact live-activity capsule: the hub's silhouette with the smaller radii
/// of the compact state, concave at the top and rounder at the bottom.
private struct NotchHubCompactSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        NotchHubSilhouette(
            topRadius: NotchHubGeometry.compactTopRadius,
            bottomRadius: NotchHubGeometry.compactBottomRadius
        )
        .path(in: rect)
    }
}

/// The compact state of the Notch hub: a capsule that hangs below the notch while something is
/// going on and the hub is closed.
///
/// It shows the symbol and the phrase of the top activity, and a `+n` badge when more are live.
/// It never shows a detail such as a file name. It is the hub's own panel in a smaller frame, it
/// is always dark, it takes no keyboard, and a click on it asks the hub to open. It is glass on
/// macOS 26 and later and a material before, opaque under Reduce Transparency and Increase
/// Contrast, as the hub is, and it appears with a short spring, or a fade under Reduce Motion.
struct NotchHubCompactView: View {
    /// What the hub says is going on.
    let board: HubActivityBoard.Board
    /// Called when the capsule is clicked.
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isShown = false

    private var prefersOpaque: Bool {
        TransparencyOptions(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
            .prefersOpaque
    }

    /// The same fill as the hub: black fading to a dark blue-grey, flat under Increase Contrast.
    private var fill: AnyShapeStyle {
        if contrast == .increased {
            AnyShapeStyle(HolzBarTheme.Hub.bottom)
        } else if prefersOpaque {
            AnyShapeStyle(HolzBarTheme.Hub.silhouetteGradient)
        } else {
            AnyShapeStyle(HolzBarTheme.Hub.translucentGradient)
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                NotchHubCompactSilhouette()
                    .fill(fill)
                    .holzBarGlass(in: NotchHubCompactSilhouette())
                content
            }
            .contentShape(NotchHubCompactSilhouette())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown || reduceMotion ? 1 : 0.85, anchor: .top)
        .onAppear {
            announce(board.compact)
            withAnimation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.snappy, reduceMotion: reduceMotion)) {
                isShown = true
            }
        }
        .onChange(of: board.compact?.key) {
            announce(board.compact)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let activity = board.compact {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Image(systemName: activity.symbol)
                    .font(HolzBarTheme.Hub.compactSymbolFont)
                    .foregroundStyle(activity.tint.color)
                    .accessibilityHidden(true)
                Text(verbatim: activity.title)
                    .font(HolzBarTheme.Hub.compactTitleFont)
                    .foregroundStyle(HolzBarTheme.Hub.pillText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if board.hiddenCount > 0 {
                    badge(board.hiddenCount)
                }
            }
            // The walls of the shape stand in by the top radius, and the content keeps a little
            // away from them.
            .padding(.horizontal, CGFloat(NotchHubGeometry.compactTopRadius) + HolzBarTheme.Spacing.xs)
            .padding(.top, CGFloat(NotchHubGeometry.compactTopRadius) / 2)
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

    /// Tells VoiceOver once that an activity started.
    private func announce(_ activity: LiveActivity?) {
        guard let activity else {
            return
        }
        AccessibilityNotification.Announcement(activity.title).post()
    }
}

/// Hosts ``NotchHubCompactView`` in the hub's panel.
///
/// The panel's frame comes from the geometry, so the view never sizes the window; the safe
/// area is zero, because the capsule hangs from the notch's strip.
final class NotchHubCompactHostingView: NSHostingView<NotchHubCompactView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(view: NotchHubCompactView) {
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: NotchHubCompactView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// The shadow follows the drawn shape, so it is worked out again after each layout.
    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }
}
