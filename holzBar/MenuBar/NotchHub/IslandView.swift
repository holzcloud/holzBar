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
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var hasKeyboardFocus: Bool

    private var canvasWidth: CGFloat {
        CGFloat(presentation.canvas.width)
    }

    private var canvasHeight: CGFloat {
        CGFloat(presentation.canvas.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            closingLayer
            island
            topRow
            content
            moduleRow
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
        .onChange(of: presentation.takesKeyboard) { _, takesKeyboard in
            // A hub that opens again while it closes keeps this view.
            if takesKeyboard {
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

    /// The transparent rest of the panel, under the island: a click in the margin of a transition
    /// or in a concave cut-out closes the hub instead of being swallowed. At rest the panel is the
    /// shape, so there is almost nothing of it.
    private var closingLayer: some View {
        Color.clear
            .frame(width: canvasWidth, height: canvasHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                host.close()
            }
            .accessibilityHidden(true)
    }

    /// The black shape, centred at the top of the canvas, with the lower-edge line under Increase
    /// Contrast. The width, the height and the corners each carry the animation that belongs to
    /// them, so the island can widen with one spring and deepen with another. Its hit area is the
    /// shape itself: a click in a concave corner or beside a rounded bottom corner never reaches
    /// the island, and the layer under it closes the hub.
    private var island: some View {
        let topRadius = CGFloat(presentation.topRadius)
        let bottomRadius = CGFloat(presentation.bottomRadius)
        return ZStack {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(HolzBarTheme.Island.surface)
            if contrast == .increased {
                IslandLowerEdge(topRadius: topRadius, bottomRadius: bottomRadius)
                    .stroke(HolzBarTheme.Island.edge, lineWidth: HolzBarTheme.Island.edgeWidth)
            }
        }
        .animation(presentation.heightAnimation, value: presentation.bottomRadius)
        .frame(width: CGFloat(presentation.width))
        .animation(presentation.widthAnimation, value: presentation.width)
        .frame(height: CGFloat(presentation.height))
        .animation(presentation.heightAnimation, value: presentation.height)
        .contentShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .offset(x: CGFloat(presentation.centreX - (presentation.canvas.x + presentation.canvas.width / 2)))
        .animation(presentation.widthAnimation, value: presentation.centreX)
        .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }

    // MARK: The content

    /// The status pills beside the notch and the settings gear below it, from the top of the
    /// shape down to the end of the context-line row. It shows only while the hub is open, never in
    /// the live state.
    @ViewBuilder
    private var topRow: some View {
        if let layout = presentation.layout {
            let area = NotchHubGeometry.Rect(
                x: layout.shape.x,
                y: layout.shape.y,
                width: layout.shape.width,
                height: layout.contextRow.maxY - layout.shape.y
            )
            staged(IslandTopRowView(model: model, layout: layout, host: host), in: area, alignment: .topLeading)
        }
    }

    /// The selected module's content or the Overview, in the layout's content rectangle.
    @ViewBuilder
    private var content: some View {
        if let area = presentation.layout?.content {
            staged(selectedContent, in: area, alignment: .top)
        }
    }

    /// The row of module buttons, in the layout's module row rectangle; it comes and goes with
    /// the content.
    @ViewBuilder
    private var moduleRow: some View {
        if let area = presentation.layout?.moduleRow {
            staged(IslandModuleRowView(model: model, fit: presentation.rowFit), in: area, alignment: .center)
        }
    }

    /// Places a part of the island at its rectangle of the layout, relative to the canvas, and
    /// stages it with the content: it appears after the shape starts to grow, from a blur and a
    /// smaller scale, and leaves first.
    private func staged(
        _ part: some View,
        in area: NotchHubGeometry.Rect,
        alignment: Alignment
    ) -> some View {
        let isShown = presentation.contentShown
        return part
            .frame(width: CGFloat(area.width), height: CGFloat(area.height), alignment: alignment)
            .blur(radius: reduceMotion || isShown ? 0 : HolzBarTheme.Island.contentBlur)
            .scaleEffect(reduceMotion || isShown ? 1 : HolzBarTheme.Island.contentScale, anchor: .top)
            .opacity(isShown ? 1 : 0)
            .animation(presentation.contentAnimation, value: isShown)
            .offset(
                x: CGFloat(area.x - presentation.canvas.x),
                y: CGFloat(area.y - presentation.canvas.y)
            )
            // A part never fades in as a view that is inserted; only its opacity moves.
            .transition(.identity)
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
