//
//  NotchHubGeometry.swift
//  holzBar
//

import Foundation

/// The pure layout of the Notch hub, in plain `Double` points inside one display.
///
/// The origin is the top-left corner of the display and y grows downward; the panel converts
/// the result to AppKit's bottom-left origin with ``flipped(_:displayHeight:)``. The numbers
/// are the design's (concept section 10b, ``DesignTokens/Island``): the hub is the notch itself,
/// growing, one black shape up to 640 points wide with concave top corners and rounded bottom
/// corners, never narrower than the notch, a context line below the notch, one module's content
/// and a row of module buttons. The notch itself is never hard-coded: it comes from the system's
/// safe-area values (``notch(displayWidth:leftAreaWidth:rightAreaWidth:height:)``), and a value
/// that makes no sense counts as no notch, so the hub hangs from the top centre.
nonisolated enum NotchHubGeometry {
    // MARK: Constants

    /// The space kept to the notch's left and right edges.
    static let clearance: Double = 8
    /// The space kept to the display's left and right edges.
    static let screenMargin: Double = 12
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

    /// The compact capsule of the live activities, relative to the display.
    nonisolated struct CompactLayout: Equatable, Sendable {
        /// The capsule, which is also the panel's frame.
        var silhouette: Rect
        /// Where the pointer rests to open the hub from the capsule: the capsule itself.
        var hoverZone: Rect
    }

    /// The rectangles of the open island, relative to the display (concept section 10b).
    nonisolated struct IslandLayout: Equatable, Sendable {
        /// The whole shape, flares included, which is also the panel's frame at rest.
        var shape: Rect
        /// The notch's rectangle, if the display has one. Nothing is placed in it.
        var notch: Rect?
        var topRowHeight: Double
        var contextRow: Rect
        var content: Rect
        var moduleRow: Rect
        /// Where the pointer rests to open the hub.
        var hoverZone: Rect
    }

    // MARK: Layout

    /// The open island on a display, or `nil` when the display has no usable size or the content
    /// height is not a number or negative.
    ///
    /// The shape is centred on the notch (on the display without one) and starts at the top. Its
    /// width is `width`, grown to the notch plus the two concave flares and capped at
    /// ``DesignTokens/Island/maximumWidth`` and the display's margins; a width that is not a number
    /// counts as ``DesignTokens/Island/baseWidth``. From the top: the top row (the notch's height,
    /// or the menu bar's where that is taller), the gap, the context line's row, the content, the
    /// gap, the module row of `buttonSize` and the space to the bottom edge. The rows lie inside
    /// the black body, which keeps the flare and the inner padding from the shape's sides. The
    /// notch is judged as the layout of the glass hub judged it: one that is not finite, not
    /// inside the display or without a height counts as none.
    static func island(
        display: Display,
        contentHeight: Double,
        width: Double,
        buttonSize: Double = DesignTokens.Island.buttonSizes[0]
    ) -> IslandLayout? {
        guard
            display.width.isFinite, display.width > 0,
            display.height.isFinite, display.height > 0,
            contentHeight.isFinite, contentHeight >= 0,
            buttonSize.isFinite, buttonSize >= 0
        else {
            return nil
        }
        let capped = min(DesignTokens.Island.maximumWidth, display.width - 2 * screenMargin)
        guard capped >= 1 else {
            return nil
        }
        let notch = validated(display.notch, in: display.width)
        let topRowHeight = resolvedTopRowHeight(of: display, notch: notch)

        let requested = width.isNaN ? DesignTokens.Island.baseWidth : width
        let narrowest = (notch.map { $0.maxX - $0.minX } ?? 0) + 2 * DesignTokens.Island.openTopRadius
        let shapeWidth = min(max(requested, narrowest), capped)

        let centre = notch.map { ($0.minX + $0.maxX) / 2 } ?? display.width / 2
        let upperBound = display.width - screenMargin - shapeWidth
        let shapeX = min(max(centre - shapeWidth / 2, screenMargin), max(upperBound, screenMargin))

        let inset = DesignTokens.Island.openTopRadius + DesignTokens.Island.sidePadding
        let bodyX = shapeX + inset
        let bodyWidth = max(shapeWidth - 2 * inset, 0)
        let contextRow = Rect(
            x: bodyX,
            y: topRowHeight + DesignTokens.Island.contextGap,
            width: bodyWidth,
            height: DesignTokens.Island.contextRowHeight
        )
        let content = Rect(x: bodyX, y: contextRow.maxY, width: bodyWidth, height: contentHeight)
        let moduleRow = Rect(
            x: bodyX,
            y: content.maxY + DesignTokens.Island.rowGap,
            width: bodyWidth,
            height: buttonSize
        )
        let shape = Rect(
            x: shapeX,
            y: 0,
            width: shapeWidth,
            height: moduleRow.maxY + DesignTokens.Island.rowBottom
        )
        let notchRect = notch.map { Rect(x: $0.minX, y: 0, width: $0.maxX - $0.minX, height: $0.height) }
        let hoverZone = notchRect ?? Rect(
            x: centre - hoverZoneWidth / 2,
            y: 0,
            width: hoverZoneWidth,
            height: hoverZoneHeight
        )
        return IslandLayout(
            shape: shape,
            notch: notchRect,
            topRowHeight: topRowHeight,
            contextRow: contextRow,
            content: content,
            moduleRow: moduleRow,
            hoverZone: hoverZone
        )
    }

    /// The height of the island's content area: a module (`overviewTileCount` is `nil`) takes the
    /// standard height, or the `preferred` one of a content that cannot scroll, kept between the
    /// standard and the largest height; a preference that is not a number counts as none. The
    /// Overview is as high as its rows of cards (``DesignTokens/Hub/columns`` to a row), within the
    /// same range, and without cards (the empty state) as high as the range allows.
    static func contentHeight(overviewTileCount: Int?, preferred: Double? = nil) -> Double {
        let smallest = DesignTokens.Island.contentHeight
        let largest = DesignTokens.Island.maximumContentHeight
        guard let overviewTileCount else {
            guard let preferred, !preferred.isNaN else {
                return smallest
            }
            return min(max(preferred, smallest), largest)
        }
        guard overviewTileCount > 0 else {
            return largest
        }
        let columns = max(DesignTokens.Hub.columns, 1)
        let rows = Double((overviewTileCount + columns - 1) / columns)
        let needed = rows * DesignTokens.Island.overviewRowHeight + (rows - 1) * DesignTokens.Island.overviewRowGap
        return min(max(needed, smallest), largest)
    }

    /// The shape every opening starts from: the notch's rectangle, or, on a display without a
    /// notch, a flat strip as wide as the hover zone at the top centre. `nil` when the display has
    /// no usable size.
    static func seed(display: Display) -> Rect? {
        guard
            display.width.isFinite, display.width > 0,
            display.height.isFinite, display.height > 0
        else {
            return nil
        }
        if let notch = validated(display.notch, in: display.width) {
            return Rect(x: notch.minX, y: 0, width: notch.maxX - notch.minX, height: notch.height)
        }
        return Rect(x: (display.width - hoverZoneWidth) / 2, y: 0, width: hoverZoneWidth, height: 0)
    }

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

    /// The compact capsule of the live activities on a display, or `nil` when the display has
    /// no usable size.
    ///
    /// The capsule hangs from the lower edge of the notch, or of the menu bar where there is no
    /// notch, so it never lies over a menu bar item. It is ``compactHeight`` high and as wide as
    /// `contentWidth`, within ``compactMinimumWidth`` (or the notch plus ``compactNotchMargin``,
    /// if that is wider) and ``compactMaximumWidth`` and inside the display's margins. It is
    /// centred on the notch, or on the display, and kept ``screenMargin`` from the edges. A width
    /// that is not a number counts as the narrowest. The notch is judged as the island's layout
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

    /// The panel's frame while the island animates from one shape to another: both shapes and
    /// ``DesignTokens/Island/transitionMargin`` more on the left, the right and the bottom, so
    /// that a spring's overshoot is never clipped. It never reaches above the top of the display
    /// or beyond its sides. At rest the panel is exactly the shape and this is not used.
    static func transitionFrame(from: Rect, to: Rect, displayWidth: Double) -> Rect {
        let margin = DesignTokens.Island.transitionMargin
        var minX = min(from.minX, to.minX) - margin
        var maxX = max(from.maxX, to.maxX) + margin
        if displayWidth.isFinite {
            minX = max(minX, 0)
            maxX = min(maxX, displayWidth)
        }
        let minY = max(min(from.minY, to.minY), 0)
        let maxY = max(from.maxY, to.maxY) + margin
        return Rect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
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
}
