//
//  IslandShape.swift
//  holzBar
//

import SwiftUI

/// The shape of the Notch hub's island: concave top corners that run into the menu bar and
/// rounded bottom corners.
///
/// The two radii are animatable data. The width and the height are not: they come from the size
/// the shape is given, so each axis can have a spring of its own (concept section 10b). The side
/// walls stand `topRadius` inside the bounds: the concave corners flare outward over that width
/// and taper to nothing at the top edge. Both radii are clamped to the bounds, because an
/// animation passes through sizes smaller than the radii.
///
/// It is `nonisolated` because SwiftUI draws a shape off the main actor.
nonisolated struct IslandShape: Shape {
    /// The radius of the concave corners at the top.
    var topRadius: CGFloat
    /// The radius of the corners at the bottom.
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = min(
            bottomRadius,
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
