//
//  IslandPresentation.swift
//  holzBar
//

import Observation
import SwiftUI

/// What the Notch hub's island shows and how it moves: the observable state the controller
/// animates and ``IslandView`` draws (concept section 10b).
///
/// The shape's size, its radii and the content's visibility are plain values. Together with each
/// change the controller sets the animation that applies to it, and the view attaches that
/// animation to the value it belongs to: the width has a spring of its own, so has the height, and
/// the content has a curve that starts a moment later. Under Reduce Motion the shape takes its
/// target at once and the content fades. Setting the animation instead of wrapping each change in
/// `withAnimation` keeps the width's spring and the height's spring apart: two changes in one turn
/// would otherwise share the transaction of the first.
///
/// Positions are in the display's coordinates (origin top-left, y down), like ``NotchHubGeometry``;
/// the panel's frame, the canvas, is the box everything is drawn in.
@MainActor
@Observable
final class IslandPresentation {
    /// The panel's frame in display coordinates: what the view fills.
    var canvas = NotchHubGeometry.Rect(x: 0, y: 0, width: 0, height: 0)

    /// The shape's centre, in display coordinates.
    var centreX: Double = 0

    /// The animated shape's size and radii, in points.
    var width: Double = 0
    var height: Double = 0
    var topRadius = DesignTokens.Island.notchTopRadius
    var bottomRadius = DesignTokens.Island.notchBottomRadius

    /// Whether the content is shown: it appears after the shape starts to grow, and leaves first.
    var contentShown = false

    /// The rectangles the open island is laid out in, or `nil` while it has none.
    var layout: NotchHubGeometry.IslandLayout?

    /// Whether the island takes the keyboard: the hotkey opened the hub.
    var takesKeyboard = false

    /// The animation of the next change of the width (and the centre), of the height (and the
    /// radii) and of the content; `nil` means the change happens at once.
    var widthAnimation: Animation?
    var heightAnimation: Animation?
    var contentAnimation: Animation?

    /// Puts the island in its closed shape, the seed, at once and without animation: the notch's
    /// rectangle with the notch's corners and no content.
    func show(seed: NotchHubGeometry.Rect, canvas: NotchHubGeometry.Rect) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            widthAnimation = nil
            heightAnimation = nil
            contentAnimation = nil
            self.canvas = canvas
            centreX = seed.x + seed.width / 2
            width = seed.width
            height = seed.height
            topRadius = DesignTokens.Island.notchTopRadius
            bottomRadius = DesignTokens.Island.notchBottomRadius
            contentShown = false
            layout = nil
        }
    }

    /// Opens the island to a layout: the shape widens with one spring and deepens with another,
    /// and the content follows 90 ms later (concept section 10b). With `reduceMotion` the shape
    /// takes its target at once and the content fades.
    func animateOpen(to layout: NotchHubGeometry.IslandLayout, reduceMotion: Bool) {
        self.layout = layout
        widthAnimation = reduceMotion ? nil : HolzBarTheme.Motion.islandOpenWidth
        heightAnimation = reduceMotion ? nil : HolzBarTheme.Motion.islandOpenHeight
        contentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentIn
        centreX = layout.shape.x + layout.shape.width / 2
        width = layout.shape.width
        height = layout.shape.height
        topRadius = DesignTokens.Island.openTopRadius
        bottomRadius = DesignTokens.Island.openBottomRadius
        contentShown = true
    }
}
