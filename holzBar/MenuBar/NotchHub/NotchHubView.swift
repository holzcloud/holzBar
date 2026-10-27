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
struct NotchHubSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let top = min(CGFloat(NotchHubGeometry.topCornerRadius), rect.width / 4, rect.height / 2)
        let bottom = min(
            CGFloat(NotchHubGeometry.bottomCornerRadius),
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

/// The content of the Notch hub's panel: the silhouette and, in the body, what the hub shows.
struct NotchHubView: View {
    let layout: NotchHubGeometry.Layout

    var body: some View {
        ZStack(alignment: .topLeading) {
            NotchHubSilhouette()
                .fill(.black)
            EmptyState(
                systemImage: "capsule.tophalf.filled",
                title: Text("No modules yet"),
                message: Text("Switch on modules in Settings and they appear here.")
            )
            .frame(width: layout.body.width, height: layout.body.height)
            .offset(x: layout.body.x - layout.silhouette.x, y: layout.body.y - layout.silhouette.y)
        }
        .frame(width: layout.silhouette.width, height: layout.silhouette.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notch hub"))
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
