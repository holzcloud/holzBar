//
//  IslandView.swift
//  holzBar
//

import SwiftUI

/// The content of the Notch hub's panel: one pure black island that grows out of the notch, and
/// the selected module's content on it (concept section 10b).
///
/// The island is one shape with no glass, no gradient and no stroke, black in every appearance, so
/// that it and the camera housing are one object. Its width and height each follow their own
/// animation (``IslandPresentation``). The content sits at a fixed rectangle of the layout and
/// never stretches with the shape: it appears a moment after the shape starts to grow, from a blur
/// and a smaller scale; under Reduce Motion nothing blurs or scales and only the opacity changes.
/// The arrow keys step through the modules while the hub has the keyboard, and Esc closes it.
struct IslandView: View {
    let presentation: IslandPresentation
    let model: NotchHubModel
    let host: any HubHost

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasKeyboardFocus: Bool

    private var canvasWidth: CGFloat {
        CGFloat(presentation.canvas.width)
    }

    private var canvasHeight: CGFloat {
        CGFloat(presentation.canvas.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            island
            content
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .focusable(presentation.takesKeyboard)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            step(by: -1)
        }
        .onKeyPress(.rightArrow) {
            step(by: 1)
        }
        .onKeyPress(.escape) {
            host.close()
            return .handled
        }
        .onAppear {
            if presentation.takesKeyboard {
                hasKeyboardFocus = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notch hub"))
    }

    /// Moves to the next or previous tab, wrapping.
    private func step(by delta: Int) -> KeyPress.Result {
        model.select(HubTabStrip.step(from: model.selectedID, by: delta, in: model.allTabIDs))
        return .handled
    }

    // MARK: The island

    /// The black shape, centred at the top of the canvas. The width, the height and the corners
    /// each carry the animation that belongs to them, so the island can widen with one spring and
    /// deepen with another.
    private var island: some View {
        IslandShape(topRadius: CGFloat(presentation.topRadius), bottomRadius: CGFloat(presentation.bottomRadius))
            .fill(HolzBarTheme.Island.surface)
            .animation(presentation.heightAnimation, value: presentation.bottomRadius)
            .frame(width: CGFloat(presentation.width))
            .animation(presentation.widthAnimation, value: presentation.width)
            .frame(height: CGFloat(presentation.height))
            .animation(presentation.heightAnimation, value: presentation.height)
            .offset(x: CGFloat(presentation.centreX - (presentation.canvas.x + presentation.canvas.width / 2)))
            .animation(presentation.widthAnimation, value: presentation.centreX)
            .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }

    // MARK: The content

    /// The selected module's content or the Overview, in the layout's content rectangle.
    @ViewBuilder
    private var content: some View {
        if let area = presentation.layout?.content {
            let isShown = presentation.contentShown
            selectedContent
                .frame(width: CGFloat(area.width), height: CGFloat(area.height), alignment: .top)
                .blur(radius: reduceMotion || isShown ? 0 : HolzBarTheme.Island.contentBlur)
                .scaleEffect(reduceMotion || isShown ? 1 : HolzBarTheme.Island.contentScale, anchor: .top)
                .opacity(isShown ? 1 : 0)
                .animation(presentation.contentAnimation, value: isShown)
                .offset(
                    x: CGFloat(area.x - presentation.canvas.x),
                    y: CGFloat(area.y - presentation.canvas.y)
                )
        }
    }

    /// The Overview, or the selected module's body. Both fill the content area, and a body that
    /// needs more scrolls inside it.
    @ViewBuilder
    private var selectedContent: some View {
        if let runtime = model.selectedRuntime {
            ScrollView {
                runtime.makeBody(host: host)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        } else {
            HubOverviewView(model: model, host: host)
        }
    }
}

/// Hosts ``IslandView`` in the panel.
///
/// The panel's frame comes from the geometry, so the view never sizes the window; the safe area
/// is zero, because the island lies over the notch's strip. It adds no shadow work of its own:
/// the window's shadow is handled where the frame is (concept section 10b).
final class IslandHostingView: NSHostingView<IslandView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(view: IslandView) {
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: IslandView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
