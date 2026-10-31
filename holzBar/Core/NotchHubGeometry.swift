//
//  NotchHubGeometry.swift
//  holzBar
//

import Foundation

/// The pure layout of the Notch hub, in plain `Double` points inside one display.
///
/// The origin is the top-left corner of the display and y grows downward; the panel converts
/// the result to AppKit's bottom-left origin with ``flipped(_:displayHeight:)``. The numbers
/// are the design's: the hub is a black silhouette up to 640 points wide with concave top
/// corners and rounded bottom corners, a left wing and a right wing beside the notch at menu
/// bar height, and a body that starts below the notch. Nothing is ever placed inside the
/// notch rectangle or within 8 points of its edges. The notch itself is never hard-coded: it
/// comes from the system's safe-area values (``notch(displayWidth:leftAreaWidth:rightAreaWidth:height:)``),
/// and a value that makes no sense counts as no notch, so the hub hangs from the top centre.
nonisolated enum NotchHubGeometry {
    // MARK: Constants

    /// The widest the hub gets.
    static let maximumWidth: Double = 640
    /// The space kept to the notch's left and right edges.
    static let clearance: Double = 8
    /// The space between the top row and the body.
    static let bodyGap: Double = 12
    /// The radius of the concave corners at the top, which run into the menu bar.
    static let topCornerRadius: Double = 28
    /// The radius of the corners at the bottom.
    static let bottomCornerRadius: Double = 30
    /// The space between the silhouette's side walls and the body. The walls stand
    /// ``topCornerRadius`` inside the silhouette's bounds, because the concave top corners
    /// flare outward over that width.
    static let bodyInset: Double = 16
    /// The space between the body and the silhouette's bottom edge.
    static let bottomPadding: Double = 16
    /// The space kept to the display's left and right edges.
    static let screenMargin: Double = 12
    /// A wing narrower than this is not drawn.
    static let minimumWingWidth: Double = 96
    /// The width of the hover zone on a display without a notch.
    static let hoverZoneWidth: Double = 200
    /// The height of the hover zone on a display without a notch: the top edge of the screen.
    static let hoverZoneHeight: Double = 3
    /// The height of the body, the same for every tab so the hub never resizes when a tab
    /// changes: two rows of widget cards (92 points and a gap of 6 fit in 190) and room to
    /// breathe. A body that needs more scrolls.
    static let bodyHeight: Double = 200
    /// The height of the top row where the display reports no usable menu bar height.
    static let fallbackMenuBarHeight: Double = 24
    /// The height of the compact capsule.
    static let compactHeight: Double = 30
    /// The narrowest the compact capsule gets, where the notch allows.
    static let compactMinimumWidth: Double = 200
    /// The widest the compact capsule gets.
    static let compactMaximumWidth: Double = 280
    /// The space the compact capsule keeps beyond the notch's width, so it is never narrower
    /// than the notch plus this.
    static let compactNotchMargin: Double = 24
    /// The radius of the compact capsule's concave corners at the top.
    static let compactTopRadius: Double = 12
    /// The radius of the compact capsule's corners at the bottom.
    static let compactBottomRadius: Double = 18

    // MARK: Values

    /// A rectangle in the display's coordinates, origin at the top-left.
    nonisolated struct Rect: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var minX: Double { x }
        var maxX: Double { x + width }
        var minY: Double { y }
        var maxY: Double { y + height }

        /// Whether the interiors overlap: rectangles that only touch do not intersect.
        func intersects(_ other: Rect) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }

        /// Whether the point is inside, edges included on all four sides: the pointer can sit
        /// on the top edge of the display.
        func contains(x pointX: Double, y pointY: Double) -> Bool {
            pointX >= minX && pointX <= maxX && pointY >= minY && pointY <= maxY
        }
    }

    /// The span the notch covers and its height.
    nonisolated struct Notch: Equatable, Sendable {
        var minX: Double
        var maxX: Double
        var height: Double
    }

    /// What the layout needs to know about a display.
    nonisolated struct Display: Equatable, Sendable {
        var width: Double
        var height: Double
        /// The height of the menu bar; the top row is at least as tall as the notch.
        var menuBarHeight: Double
        var notch: Notch?
    }

    /// What the body holds.
    nonisolated struct Content: Equatable, Sendable {
        var bodyHeight: Double
    }

    /// The rectangles of the hub, relative to the display.
    nonisolated struct Layout: Equatable, Sendable {
        /// The whole shape, which is also the panel's frame.
        var silhouette: Rect
        /// The notch's rectangle, if the display has one. Nothing is placed in it.
        var notch: Rect?
        /// The left wing, at menu bar height, or `nil` where it would be narrower than
        /// ``NotchHubGeometry/minimumWingWidth``.
        var leftWing: Rect?
        /// The right wing, or `nil` where it would be too narrow.
        var rightWing: Rect?
        var body: Rect
        /// Where the pointer rests to open the hub.
        var hoverZone: Rect
        var topRowHeight: Double
    }

    /// The compact capsule of the live activities, relative to the display.
    nonisolated struct CompactLayout: Equatable, Sendable {
        /// The capsule, which is also the panel's frame.
        var silhouette: Rect
        /// Where the pointer rests to open the hub from the capsule: the capsule itself.
        var hoverZone: Rect
    }

    // MARK: Layout

    /// The notch from the widths of the unobscured areas beside it, as
    /// `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` report them, or `nil` for a
    /// display without one.
    static func notch(
        displayWidth: Double,
        leftAreaWidth: Double?,
        rightAreaWidth: Double?,
        height: Double
    ) -> Notch? {
        guard let leftAreaWidth, let rightAreaWidth else {
            return nil
        }
        return validated(Notch(minX: leftAreaWidth, maxX: displayWidth - rightAreaWidth, height: height), in: displayWidth)
    }

    /// The layout of the hub on a display, or `nil` when the display has no usable size.
    ///
    /// A notch that is not finite, not inside the display or without a height counts as none.
    static func layout(display: Display, content: Content) -> Layout? {
        guard
            display.width.isFinite, display.width > 0,
            display.height.isFinite, display.height > 0,
            content.bodyHeight.isFinite, content.bodyHeight >= 0
        else {
            return nil
        }
        let width = min(maximumWidth, display.width - 2 * screenMargin)
        guard width >= 1 else {
            return nil
        }
        let notch = validated(display.notch, in: display.width)
        let topRowHeight = resolvedTopRowHeight(of: display, notch: notch)

        let centre = notch.map { ($0.minX + $0.maxX) / 2 } ?? display.width / 2
        let upperBound = display.width - screenMargin - width
        let silhouetteX = min(max(centre - width / 2, screenMargin), max(upperBound, screenMargin))

        let body = Rect(
            x: silhouetteX + topCornerRadius + bodyInset,
            y: topRowHeight + bodyGap,
            width: width - 2 * (topCornerRadius + bodyInset),
            height: content.bodyHeight
        )
        let silhouette = Rect(x: silhouetteX, y: 0, width: width, height: body.maxY + bottomPadding)

        let leftStart = silhouette.minX + topCornerRadius
        let rightEnd = silhouette.maxX - topCornerRadius
        let leftEnd = notch.map { $0.minX - clearance } ?? centre - clearance / 2
        let rightStart = notch.map { $0.maxX + clearance } ?? centre + clearance / 2

        let notchRect = notch.map { Rect(x: $0.minX, y: 0, width: $0.maxX - $0.minX, height: $0.height) }
        let hoverZone = notchRect ?? Rect(
            x: centre - hoverZoneWidth / 2,
            y: 0,
            width: hoverZoneWidth,
            height: hoverZoneHeight
        )
        return Layout(
            silhouette: silhouette,
            notch: notchRect,
            leftWing: wing(from: leftStart, to: leftEnd, height: topRowHeight),
            rightWing: wing(from: rightStart, to: rightEnd, height: topRowHeight),
            body: body,
            hoverZone: hoverZone,
            topRowHeight: topRowHeight
        )
    }

    /// The compact capsule of the live activities on a display, or `nil` when the display has
    /// no usable size.
    ///
    /// The capsule hangs from the lower edge of the notch, or of the menu bar where there is no
    /// notch, so it never lies over a menu bar item. It is ``compactHeight`` high and as wide as
    /// `contentWidth`, within ``compactMinimumWidth`` (or the notch plus ``compactNotchMargin``,
    /// if that is wider) and ``compactMaximumWidth`` and inside the display's margins. It is
    /// centred on the notch, or on the display, and kept ``screenMargin`` from the edges. A width
    /// that is not a number counts as the narrowest. The notch is judged as ``layout(display:content:)``
    /// judges it.
    static func compactLayout(display: Display, contentWidth: Double) -> CompactLayout? {
        guard
            display.width.isFinite, display.width > 0,
            display.height.isFinite, display.height > 0
        else {
            return nil
        }
        let available = display.width - 2 * screenMargin
        guard available >= 1 else {
            return nil
        }
        let notch = validated(display.notch, in: display.width)
        let narrowest = max(compactMinimumWidth, (notch.map { $0.maxX - $0.minX } ?? 0) + compactNotchMargin)
        let requested = contentWidth.isNaN ? narrowest : contentWidth
        let width = min(min(max(requested, narrowest), compactMaximumWidth), available)

        let centre = notch.map { ($0.minX + $0.maxX) / 2 } ?? display.width / 2
        let upperBound = display.width - screenMargin - width
        let x = min(max(centre - width / 2, screenMargin), max(upperBound, screenMargin))
        let rect = Rect(x: x, y: resolvedTopRowHeight(of: display, notch: notch), width: width, height: compactHeight)
        return CompactLayout(silhouette: rect, hoverZone: rect)
    }

    /// The same rectangle in AppKit's coordinates, whose origin is the bottom-left corner of the
    /// display. Only y changes.
    static func flipped(_ rect: Rect, displayHeight: Double) -> Rect {
        Rect(x: rect.x, y: displayHeight - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    // MARK: Helpers

    /// The notch if it is finite, has a height and lies inside the display; otherwise `nil`.
    private static func validated(_ notch: Notch?, in displayWidth: Double) -> Notch? {
        guard
            let notch,
            notch.minX.isFinite, notch.maxX.isFinite, notch.height.isFinite,
            notch.minX >= 0, notch.minX < notch.maxX, notch.maxX <= displayWidth,
            notch.height > 0
        else {
            return nil
        }
        return notch
    }

    /// The height of the top row: the menu bar, or the notch if that is taller. A menu bar height
    /// that makes no sense falls back to ``fallbackMenuBarHeight``.
    private static func resolvedTopRowHeight(of display: Display, notch: Notch?) -> Double {
        let menuBarHeight = display.menuBarHeight.isFinite && display.menuBarHeight > 0
            ? display.menuBarHeight
            : fallbackMenuBarHeight
        return max(menuBarHeight, notch?.height ?? 0)
    }

    private static func wing(from start: Double, to end: Double, height: Double) -> Rect? {
        let width = end - start
        guard width >= minimumWingWidth else {
            return nil
        }
        return Rect(x: start, y: 0, width: width, height: height)
    }
}
