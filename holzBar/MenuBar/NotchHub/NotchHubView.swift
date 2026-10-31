//
//  NotchHubView.swift
//  holzBar
//

import SwiftUI

/// The shape of the Notch hub: a silhouette whose top corners are concave, so that it runs
/// into the menu bar, and whose bottom corners are rounded.
///
/// The side walls stand ``NotchHubGeometry/topCornerRadius`` inside the bounds: the concave
/// corners flare outward over that width and taper to nothing at the top edge.
nonisolated struct NotchHubSilhouette: Shape {
    /// The radius of the concave corners at the top.
    var topRadius = NotchHubGeometry.topCornerRadius
    /// The radius of the corners at the bottom.
    var bottomRadius = NotchHubGeometry.bottomCornerRadius

    func path(in rect: CGRect) -> Path {
        let top = min(CGFloat(topRadius), rect.width / 4, rect.height / 2)
        let bottom = min(
            CGFloat(bottomRadius),
            max(rect.width / 2 - top, 0),
            max(rect.height - top, 0)
        )
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Concave corner, top right: tangent to the top edge and to the right wall.
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - top, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            radius: top
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - top, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + top, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + top, y: rect.maxY - bottom),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + top))
        // Concave corner, top left.
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + top, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY),
            radius: top
        )
        path.closeSubpath()
        return path
    }
}

/// The content of the Notch hub's panel: the silhouette, the icon row across both wings, the
/// status pills and the settings button at the far right of the right wing, and the body below.
///
/// Everything is placed in the rectangles of ``NotchHubGeometry``, relative to the silhouette;
/// nothing is placed in the notch. The hub is always dark. It opens with one bounce and a glass
/// morph from the notch's size on macOS 26 and later, and with a short fade before, under
/// Reduce Motion, Reduce Transparency and Increase Contrast.
struct NotchHubView: View {
    let layout: NotchHubGeometry.Layout
    let model: NotchHubModel
    let host: any HubHost
    /// Whether the hub takes the keyboard: the hotkey opened it.
    let takesKeyboard: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isShown = false
    @FocusState private var hasKeyboardFocus: Bool

    private var origin: CGPoint {
        CGPoint(x: layout.silhouette.x, y: layout.silhouette.y)
    }

    private var size: CGSize {
        CGSize(width: layout.silhouette.width, height: layout.silhouette.height)
    }

    /// Whether the silhouette is opaque: Reduce Transparency or Increase Contrast.
    private var prefersOpaque: Bool {
        TransparencyOptions(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
            .prefersOpaque
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            silhouette
            parts
                .opacity(isShown ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .focusable(takesKeyboard)
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
            if takesKeyboard {
                hasKeyboardFocus = true
            }
            withAnimation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.hub, reduceMotion: reduceMotion)) {
                isShown = true
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

    // MARK: Silhouette

    /// What the silhouette is filled with: black fading to a dark blue-grey, flat under
    /// Increase Contrast, and with a bottom that lets glass show through where there is glass.
    private var fill: AnyShapeStyle {
        if contrast == .increased {
            AnyShapeStyle(HolzBarTheme.Hub.bottom)
        } else if prefersOpaque {
            AnyShapeStyle(HolzBarTheme.Hub.silhouetteGradient)
        } else {
            AnyShapeStyle(HolzBarTheme.Hub.translucentGradient)
        }
    }

    @ViewBuilder
    private var silhouette: some View {
        if #available(macOS 26.0, *), !reduceMotion, !prefersOpaque {
            HubMorphingSilhouette(isShown: isShown, size: size, seed: seed, fill: fill)
        } else {
            NotchHubSilhouette()
                .fill(fill)
                .frame(width: size.width, height: size.height)
                .holzBarGlass(in: NotchHubSilhouette())
                .opacity(isShown ? 1 : 0)
        }
    }

    /// The shape the hub grows from, relative to the silhouette: the size of the notch where
    /// there is one, otherwise a pill at the top centre. It only gives the morph its start.
    private var seed: CGRect {
        if let notch = layout.notch {
            return CGRect(x: notch.x - origin.x, y: 0, width: notch.width, height: notch.height)
        }
        let width = NotchHubGeometry.hoverZoneWidth
        return CGRect(
            x: (layout.silhouette.width - width) / 2,
            y: 0,
            width: width,
            height: layout.topRowHeight
        )
    }

    // MARK: Parts

    /// The tab row across both wings, decided once for both of them.
    private var row: HubTabStrip.Row {
        HubTabStrip.row(
            moduleTabs: model.tabModuleIDs,
            selected: model.selectedID,
            leftWingWidth: layout.leftWing?.width ?? 0,
            rightWingWidth: layout.rightWing?.width ?? 0,
            rightReservedWidth: reservedRightWidth
        )
    }

    /// What the status pills and the settings button need at the far right of the right wing.
    private var reservedRightWidth: Double {
        HubTabStrip.rightReservedWidth(
            pills: model.pills.map { HubTabStrip.Pill(textLength: $0.pill.text.count, hasSymbol: $0.pill.symbol != nil) }
        )
    }

    private var parts: some View {
        let row = row
        return ZStack(alignment: .topLeading) {
            if let left = layout.leftWing {
                HubTabStripView(
                    model: model,
                    ids: row.left,
                    selected: row.selected,
                    tabWidth: CGFloat(row.tabWidth),
                    rowHeight: left.height,
                    overflow: row.moreWing == .left ? row.overflow : []
                )
                .frame(width: left.width, height: left.height, alignment: .leading)
                .clipped()
                .offset(x: left.x - origin.x, y: left.y - origin.y)
            }
            if let right = layout.rightWing {
                HubRightWingView(
                    model: model,
                    host: host,
                    row: row,
                    wingWidth: right.width,
                    rowHeight: right.height,
                    reservedWidth: reservedRightWidth
                )
                .offset(x: right.x - origin.x, y: right.y - origin.y)
            }
            bodyArea
                .frame(width: layout.body.width, height: layout.body.height)
                .offset(x: layout.body.x - origin.x, y: layout.body.y - origin.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The Overview, or the selected module's body. Both fill the one body area, and a body
    /// that needs more scrolls.
    @ViewBuilder
    private var bodyArea: some View {
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

/// The silhouette on Liquid Glass (macOS 26 and later) that grows from the notch's size to its
/// own, by a glass morph: the same `glassEffectID` before and after, in one container.
@available(macOS 26.0, *)
private struct HubMorphingSilhouette: View {
    let isShown: Bool
    let size: CGSize
    let seed: CGRect
    let fill: AnyShapeStyle

    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            ZStack(alignment: .topLeading) {
                if isShown {
                    NotchHubSilhouette()
                        .fill(fill)
                        .frame(width: size.width, height: size.height)
                        .glassEffect(.regular, in: NotchHubSilhouette())
                        .glassEffectID("hub", in: namespace)
                } else {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: HolzBarTheme.Radius.control,
                        bottomTrailingRadius: HolzBarTheme.Radius.control,
                        style: .continuous
                    )
                    .fill(fill)
                    .frame(width: seed.width, height: seed.height)
                    .glassEffect(
                        .regular,
                        in: UnevenRoundedRectangle(
                            bottomLeadingRadius: HolzBarTheme.Radius.control,
                            bottomTrailingRadius: HolzBarTheme.Radius.control,
                            style: .continuous
                        )
                    )
                    .glassEffectID("hub", in: namespace)
                    .offset(x: seed.minX, y: seed.minY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// Hosts ``NotchHubView`` in the panel.
///
/// The panel's frame comes from the geometry, so the view never sizes the window; the safe
/// area is zero, because the hub lies over the notch's strip.
final class NotchHubHostingView: NSHostingView<NotchHubView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(view: NotchHubView) {
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: NotchHubView) {
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
