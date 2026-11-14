//
//  NotchHubGeometry.swift
//  holzBar
//

import Foundation

/// The pure layout of the Notch hub, in plain `Double` points inside one display.
///
/// The origin is the top-left corner of the display and y grows downward; the panel converts
/// the result to AppKit's bottom-left origin with ``flipped(_:displayHeight:)``. The numbers
/// are the design's (concept section 10b, ``DesignTokens/Island``). It holds:
///
/// - the open island (``island(display:contentHeight:width:buttonSize:)``): one black shape up to
///   640 points wide with concave top corners and rounded bottom corners, never narrower than the
///   notch, a context line below the notch, one module's content and a row of module buttons,
///   and the height of that content (``contentHeight(overviewTileCount:preferred:)``);
/// - the seed (``seed(display:)``), the shape every opening starts from;
/// - the panel's frame while the island moves (``transitionFrame(from:to:displayWidth:)``);
/// - the live state (``live(display:room:)``): while the hub is closed and something is live, the
///   same shape is the notch widened at menu bar height, only over the free menu bar
///   (``liveRoom(display:leftContentEnd:rightContentStart:)``).
///
/// The notch itself is never hard-coded: it comes from the system's safe-area values
/// (``notch(displayWidth:leftAreaWidth:rightAreaWidth:height:)``), and a value that makes no
/// sense counts as no notch, so the hub hangs from the top centre.
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
    /// The height of the top row where the display reports no usable menu bar height.
    static let fallbackMenuBarHeight: Double = 24

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

    /// The live state: the notch widened at menu bar height (concept section 10b).
    nonisolated struct LiveLayout: Equatable, Sendable {
        /// The whole shape, flares included, which is also the panel's frame.
        var shape: Rect
        /// The area left of the notch where the live symbol goes; it ends ``clearance`` before the
        /// notch (half of it from the centre without a notch).
        var leading: Rect
        /// The area right of the notch where the live value goes.
        var trailing: Rect
        /// Where the pointer rests to open the hub from the live state: the shape itself.
        var hoverZone: Rect
    }

    /// How much of the menu bar beside the notch is free, in points, measured from the notch's
    /// edge (the display's centre without a notch) outward on each side: the space the live
    /// state may widen into without covering anything (concept section 10b, 2026-11-14).
    nonisolated struct LiveRoom: Equatable, Sendable {
        var left: Double
        var right: Double

        /// Nothing limits either side but the maximum width and the display's margins: the
        /// answer where holzBar does not know what the menu bar holds.
        static let unlimited = LiveRoom(left: .infinity, right: .infinity)
    }

    // MARK: Layout

    /// The free room beside the notch from where the menu bar's content is, or `nil` for a side
    /// that holds nothing.
    ///
    /// `leftContentEnd` is where the application menu ends and `rightContentStart` where the run
    /// of status items starts, both in x from the display's left edge. Each side's room runs from
    /// the notch's edge (the display's centre without a notch) to that content, less
    /// ``DesignTokens/Island/liveContentGap``; a content that reaches the notch, or lies beyond
    /// it, leaves none. A position that is not a number counts as covering its side (no room),
    /// and a display that makes no sense has no room at all.
    static func liveRoom(display: Display, leftContentEnd: Double?, rightContentStart: Double?) -> LiveRoom {
        guard display.width.isFinite, display.width > 0 else {
            return LiveRoom(left: 0, right: 0)
        }
        let notch = validated(display.notch, in: display.width)
        let axisLeft = notch?.minX ?? display.width / 2
        let axisRight = notch?.maxX ?? display.width / 2
        let gap = DesignTokens.Island.liveContentGap
        let left: Double
        if let leftContentEnd {
            left = leftContentEnd.isFinite ? max(axisLeft - (leftContentEnd + gap), 0) : 0
        } else {
            left = .infinity
        }
        let right: Double
        if let rightContentStart {
            right = rightContentStart.isFinite ? max((rightContentStart - gap) - axisRight, 0) : 0
        } else {
            right = .infinity
        }
        return LiveRoom(left: left, right: right)
    }

    /// The live state on a display, or `nil` when the display has no usable size or no side has
    /// room for it.
    ///
    /// The shape starts at the top edge and is exactly the top row high, so it never grows
    /// downward and never covers more of the menu bar than the notch's own row. It grows only
    /// over the free menu bar (concept section 10b, 2026-11-14): on each side its black part
    /// reaches at most ``DesignTokens/Island/liveSideWidth`` beyond the notch (the display's
    /// centre without a notch) and at most as far as `room` allows, and the bounds add
    /// ``DesignTokens/Island/liveTopRadius`` for the concave flare, which must lie inside the room
    /// as well. A side is also kept ``screenMargin`` from the display's edge. A side whose black
    /// part would be narrower than ``DesignTokens/Island/liveMinimumSideWidth`` does not widen at
    /// all: its edge is the notch's edge, it has no flare and its area is empty. The sides are
    /// decided separately, so the shape need not be symmetric; when neither widens there is no
    /// live state and the result is `nil`. The leading area ends ``clearance`` before the notch and
    /// the trailing area starts ``clearance`` after it (half of it from the centre without a
    /// notch). The notch is judged as the island's layout judges it.
    ///
    /// - Parameter room: The free menu bar on each side. A room that is not a number counts as
    ///   none; the default is no limit but the maximum and the margins.
    static func live(display: Display, room: LiveRoom = .unlimited) -> LiveLayout? {
        guard
            display.width.isFinite, display.width > 0,
            display.height.isFinite, display.height > 0
        else {
            return nil
        }
        let capped = display.width - 2 * screenMargin
        guard capped >= 1 else {
            return nil
        }
        let notch = validated(display.notch, in: display.width)
        let topRowHeight = resolvedTopRowHeight(of: display, notch: notch)

        let radius = DesignTokens.Island.liveTopRadius
        let axisLeft = notch?.minX ?? display.width / 2
        let axisRight = notch?.maxX ?? display.width / 2
        let leftBlack = blackWidth(room: room.left, limit: axisLeft - screenMargin)
        let rightBlack = blackWidth(room: room.right, limit: display.width - screenMargin - axisRight)
        guard leftBlack > 0 || rightBlack > 0 else {
            return nil
        }
        let shapeMinX = axisLeft - (leftBlack > 0 ? leftBlack + radius : 0)
        let shapeMaxX = axisRight + (rightBlack > 0 ? rightBlack + radius : 0)
        let shape = Rect(x: shapeMinX, y: 0, width: shapeMaxX - shapeMinX, height: topRowHeight)

        let blackMinX = shape.minX + radius
        let blackMaxX = shape.maxX - radius
        let leadingEnd = notch.map { $0.minX - clearance } ?? axisLeft - clearance / 2
        let trailingStart = notch.map { $0.maxX + clearance } ?? axisRight + clearance / 2
        let leadingX = min(blackMinX, leadingEnd)
        let trailingEnd = max(blackMaxX, trailingStart)
        return LiveLayout(
            shape: shape,
            leading: Rect(x: leadingX, y: 0, width: max(leadingEnd - leadingX, 0), height: topRowHeight),
            trailing: Rect(x: trailingStart, y: 0, width: max(trailingEnd - trailingStart, 0), height: topRowHeight),
            hoverZone: shape
        )
    }

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

    /// How far the live state's black part reaches beyond the notch on one side: at most
    /// ``DesignTokens/Island/liveSideWidth``, within the free `room` and the `limit` that keeps the
    /// display's margin (the flare lies inside both), or 0 when that is narrower than
    /// ``DesignTokens/Island/liveMinimumSideWidth``.
    private static func blackWidth(room: Double, limit: Double) -> Double {
        let free = room.isNaN ? 0 : room
        let available = min(free, limit) - DesignTokens.Island.liveTopRadius
        let width = min(DesignTokens.Island.liveSideWidth, available)
        return width >= DesignTokens.Island.liveMinimumSideWidth ? width : 0
    }

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
