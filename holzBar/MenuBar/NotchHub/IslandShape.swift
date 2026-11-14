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

    /// Both radii, kept inside the bounds: the top radius within a quarter of the width and half
    /// the height, the bottom radius within what is left of the width and the height.
    static func clamped(_ topRadius: CGFloat, _ bottomRadius: CGFloat, in rect: CGRect) -> (top: CGFloat, bottom: CGFloat) {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = min(
            bottomRadius,
            max(rect.width / 2 - top, 0),
            max(rect.height - top, 0)
        )
        return (top, bottom)
    }

    func path(in rect: CGRect) -> Path {
        let (top, bottom) = Self.clamped(topRadius, bottomRadius, in: rect)
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

/// The lower edge of the island, as an open path: Increase Contrast strokes it with a thin white
/// line along the bottom only (concept section 10b), where the island meets a dark wallpaper.
///
/// It follows ``IslandShape``: up from the left wall at the start of the bottom-left arc, the arc,
/// the bottom line, the bottom-right arc, ending on the right wall, with the same radii and the
/// same clamps. The path lies half of ``DesignTokens/Island/edgeWidth`` inside the shape, so the
/// stroke stays inside the black and never reaches the panel's edge.
///
/// It is `nonisolated` because SwiftUI draws a shape off the main actor.
nonisolated struct IslandLowerEdge: Shape {
    /// The radius of the concave corners at the top, which sets where the side walls stand.
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
        let (top, shapeBottom) = IslandShape.clamped(topRadius, bottomRadius, in: rect)
        let inset = CGFloat(DesignTokens.Island.edgeWidth) / 2
        let left = rect.minX + top + inset
        let right = rect.maxX - top - inset
        let bottomY = rect.maxY - inset
        let radius = max(min(shapeBottom - inset, (right - left) / 2, bottomY - rect.minY), 0)
        var path = Path()
        path.move(to: CGPoint(x: left, y: bottomY - radius))
        path.addArc(
            tangent1End: CGPoint(x: left, y: bottomY),
            tangent2End: CGPoint(x: left + radius, y: bottomY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: right - radius, y: bottomY))
        path.addArc(
            tangent1End: CGPoint(x: right, y: bottomY),
            tangent2End: CGPoint(x: right, y: bottomY - radius),
            radius: radius
        )
        return path
    }
}
