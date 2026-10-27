//
//  HolzBarShelfPlacement.swift
//  holzBar
//

import Foundation

/// Where the holzBar Shelf's panel goes: one pure function for both styles and every anchor.
///
/// All numbers are plain `Double` values in AppKit's coordinates: the origin is the bottom
/// left of the global screen space and y grows upward, so the menu bar is at the top of a
/// screen's `frame`. The function never reads the screen or the pointer; the caller does,
/// once, when the Shelf opens.
///
/// - Attached: the panel hangs directly below the menu bar and is centred on the anchor,
///   clamped into the screen's frame. This is the arithmetic the panel always had, moved out
///   of it: the origin's y is `(frame.maxY - 1 - menuBarHeight) - panel.height`. The pointer's
///   height and the insets are ignored. The screen edge puts the panel flush right.
/// - Floating: the panel is larger than the bar by transparent `insets` that hold its shadow.
///   The bar's top is `floatingGap` below the menu bar, and the bar is centred on the anchor,
///   clamped into the visible frame less `floatingMargin` on the left, right and bottom (so the
///   Dock is respected). The screen edge puts the bar's right side at that margin. Under the
///   pointer the bar's top is `pointerOffset` below it; where that would put the bar's bottom
///   below the visible area, the bar's bottom is `pointerOffset` above the pointer instead.
///   Neither way fits for a bar taller than the room, which keeps its top below the menu bar
///   and lets the visible frame clip its bottom.
///
/// The insets' top is 0 so the transparent panel never overlaps the menu bar's clickable
/// lower edge, and the rehide checks, which pad the panel by 15 points, still count the
/// pointer's way from the menu bar to the bar as inside it.
nonisolated enum HolzBarShelfPlacement {
    /// A point in AppKit's coordinates.
    nonisolated struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    /// A size.
    nonisolated struct Size: Equatable, Sendable {
        var width: Double
        var height: Double
    }

    /// A rectangle given by its bottom left corner and its size.
    nonisolated struct Rect: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var minX: Double { x }
        var maxX: Double { x + width }
        var minY: Double { y }
        var maxY: Double { y + height }

        var isFinite: Bool {
            x.isFinite && y.isFinite && width.isFinite && height.isFinite
        }
    }

    /// The transparent margins between the panel's edges and the bar, in points.
    nonisolated struct Insets: Equatable, Sendable {
        var top: Double
        var leading: Double
        var bottom: Double
        var trailing: Double

        static let zero = Insets(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    /// What the placement needs to know about the screen the Shelf opens on.
    nonisolated struct Screen: Equatable, Sendable {
        /// The screen's whole frame.
        var frame: Rect
        /// The part not covered by the Dock or the menu bar.
        var visibleFrame: Rect
        /// The menu bar's height, 0 when it is hidden or unknown.
        var menuBarHeight: Double
    }

    /// What the Shelf centres on, read once when it opens and kept while it is open.
    nonisolated enum Anchor: Equatable, Sendable {
        /// The horizontal centre of the holzBar icon.
        case horizontal(Double)
        /// The mouse pointer.
        case pointer(x: Double, y: Double)
        /// The right edge of the screen.
        case screenEdge
    }

    /// The space between the menu bar's lower edge and the floating bar's top.
    static let floatingGap: Double = 8

    /// The space between the floating bar and the edges of the visible frame.
    static let floatingMargin: Double = 8

    /// The space between the pointer and the floating bar's near edge.
    static let pointerOffset: Double = 12

    /// The transparent margins of the floating panel, which hold the bar's shadow.
    static let floatingInsets = Insets(top: 0, leading: 12, bottom: 16, trailing: 12)

    /// The panel's bottom left corner.
    ///
    /// - Parameters:
    ///   - style: Attached or floating.
    ///   - anchor: What the panel is centred on.
    ///   - panel: The panel's size, with its insets.
    ///   - screen: The screen the panel opens on.
    ///   - insets: The panel's transparent margins; the attached style ignores them.
    /// - Returns: A finite point for any input; the screen's bottom left corner when the
    ///   panel's size is unusable.
    static func origin(
        style: HolzBarShelfStyle,
        anchor: Anchor,
        panel: Size,
        screen: Screen,
        insets: Insets
    ) -> Point {
        guard screen.frame.isFinite, screen.visibleFrame.isFinite else {
            return Point(x: 0, y: 0)
        }
        guard
            panel.width.isFinite, panel.height.isFinite,
            panel.width > 0, panel.height > 0
        else {
            return Point(x: screen.frame.minX, y: screen.frame.minY)
        }

        // An anchor that is not a number counts as the screen edge.
        let anchorX: Double?
        let pointerY: Double?
        switch anchor {
        case .horizontal(let x):
            anchorX = x.isFinite ? x : nil
            pointerY = nil
        case .pointer(let x, let y):
            anchorX = x.isFinite ? x : nil
            pointerY = x.isFinite && y.isFinite ? y : nil
        case .screenEdge:
            anchorX = nil
            pointerY = nil
        }
        let menuBarHeight = menuBarHeight(of: screen)

        let result: Point
        switch style {
        case .attached:
            result = attachedOrigin(anchorX: anchorX, panel: panel, frame: screen.frame, menuBarHeight: menuBarHeight)
        case .floating:
            result = floatingOrigin(
                anchorX: anchorX,
                pointerY: pointerY,
                panel: panel,
                screen: screen,
                menuBarHeight: menuBarHeight,
                insets: insets
            )
        }
        // Numbers so large that the sums overflow still give a defined origin.
        guard result.x.isFinite, result.y.isFinite else {
            return Point(x: screen.frame.minX, y: screen.frame.minY)
        }
        return result
    }

    // MARK: Shape

    /// The corner radius of the floating bar for a bar of the given height: half of it, so a
    /// one-row bar is a capsule, and at most the panel radius of the design, so a taller bar
    /// (a grid or a column) is a rounded panel. Zero for a height that is not usable.
    static func floatingCornerRadius(forHeight height: Double) -> Double {
        guard height.isFinite, height > 0 else {
            return 0
        }
        return min(height / 2, DesignTokens.Radius.panel)
    }

    // MARK: Attached

    private static func attachedOrigin(
        anchorX: Double?,
        panel: Size,
        frame: Rect,
        menuBarHeight: Double
    ) -> Point {
        let lower = frame.minX
        let upper = frame.maxX - panel.width
        let x: Double
        if let anchorX, lower <= upper {
            x = clamp(anchorX - panel.width / 2, lower, upper)
        } else {
            x = upper
        }
        let y = ((frame.maxY - 1) - menuBarHeight) - panel.height
        return Point(x: x, y: y)
    }

    // MARK: Floating

    private static func floatingOrigin(
        anchorX: Double?,
        pointerY: Double?,
        panel: Size,
        screen: Screen,
        menuBarHeight: Double,
        insets: Insets
    ) -> Point {
        let insets = usable(insets)
        let barWidth = max(panel.width - insets.leading - insets.trailing, 0)
        let barHeight = max(panel.height - insets.top - insets.bottom, 0)

        // The room the bar may use: the visible frame less a margin on the left, right and
        // bottom. Its top is the ceiling, which keeps the panel clear of the menu bar.
        let areaMinX = screen.visibleFrame.minX + floatingMargin
        let areaMaxX = screen.visibleFrame.maxX - floatingMargin
        let areaMinY = screen.visibleFrame.minY + floatingMargin
        let ceiling = ((screen.frame.maxY - menuBarHeight) - floatingGap) - insets.top

        let rightLimit = areaMaxX - barWidth
        let barX: Double
        if let anchorX, areaMinX <= rightLimit {
            barX = clamp(anchorX - barWidth / 2, areaMinX, rightLimit)
        } else {
            barX = rightLimit
        }

        var barTop = ceiling
        if let pointerY {
            barTop = pointerBarTop(
                pointerY: pointerY,
                barHeight: barHeight,
                ceiling: ceiling,
                areaMinY: areaMinY
            )
        }

        return Point(x: barX - insets.leading, y: (barTop - barHeight) - insets.bottom)
    }

    /// The top of a bar that hangs from the pointer: below it when the bar fits there, else
    /// above it when the bar fits there, else as low as the room allows.
    private static func pointerBarTop(
        pointerY: Double,
        barHeight: Double,
        ceiling: Double,
        areaMinY: Double
    ) -> Double {
        let below = min(pointerY - pointerOffset, ceiling)
        if below - barHeight >= areaMinY {
            return below
        }
        let aboveTop = (pointerY + pointerOffset) + barHeight
        if aboveTop <= ceiling {
            return aboveTop
        }
        // Neither side of the pointer has room: the bar covers the pointer, as low as the
        // area allows, and a bar taller than the room hangs from the ceiling.
        return min(ceiling, areaMinY + barHeight)
    }

    // MARK: Helpers

    /// The menu bar's height, 0 when it is not a usable number.
    private static func menuBarHeight(of screen: Screen) -> Double {
        screen.menuBarHeight.isFinite ? max(screen.menuBarHeight, 0) : 0
    }

    /// Insets that are finite and not negative.
    private static func usable(_ insets: Insets) -> Insets {
        func part(_ value: Double) -> Double {
            value.isFinite ? max(value, 0) : 0
        }
        return Insets(
            top: part(insets.top),
            leading: part(insets.leading),
            bottom: part(insets.bottom),
            trailing: part(insets.trailing)
        )
    }

    /// `value` limited to `lower...upper`, which must not be inverted.
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
