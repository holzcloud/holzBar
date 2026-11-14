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

    /// How the row of module buttons is drawn: the buttons' size, and whether it scrolls. Worked
    /// out when the hub opens; a module switched on or off while it is open changes the row at
    /// the next opening.
    var rowFit = HubModuleRow.Fit(
        buttonSize: DesignTokens.Island.buttonSizes.first ?? 30,
        hubWidth: DesignTokens.Island.baseWidth,
        scrolls: false
    )

    /// Whether the island takes the keyboard: the hotkey opened the hub.
    var takesKeyboard = false

    /// The animation of the next change of the width (and the centre), of the height (and the
    /// radii) and of the content; `nil` means the change happens at once.
    var widthAnimation: Animation?
    var heightAnimation: Animation?
    var contentAnimation: Animation?

    /// The generation of the transition that runs, so that a completion that arrives late never
    /// changes the shape of a newer one.
    @ObservationIgnored private var transitionGeneration = 0

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
    ///
    /// `completion` runs once, with `generation`, when the whole transition has settled. Every
    /// change goes through one `withAnimation` call, so that one transaction carries the
    /// completion; a second, earlier change in the same turn would take the transaction for
    /// itself.
    func animateOpen(
        to layout: NotchHubGeometry.IslandLayout,
        reduceMotion: Bool,
        generation: Int,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        transitionGeneration = generation
        let driver = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandOpenHeight
        withAnimation(driver, completionCriteria: .removed) {
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
        } completion: {
            completion(generation)
        }
    }

    /// Closes the island into `rest`, the notch's rectangle (concept section 10b): the content
    /// goes first, in 0.12 s with its opacity and blur, then the shape returns with a spring that
    /// does not overshoot. With `reduceMotion` only the content fades, in 0.15 s, and the shape
    /// then takes `rest` at once.
    ///
    /// `completion` runs once, with `generation`, when the closing has finished. The shape of a
    /// closing that a newer transition replaced is left alone.
    func animateClose(
        to rest: NotchHubGeometry.Rect,
        topRadius: Double,
        bottomRadius: Double,
        reduceMotion: Bool,
        generation: Int,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        transitionGeneration = generation
        if reduceMotion {
            withAnimation(HolzBarTheme.Motion.reduced, completionCriteria: .removed) {
                widthAnimation = nil
                heightAnimation = nil
                contentAnimation = HolzBarTheme.Motion.reduced
                contentShown = false
            } completion: { [weak self] in
                if let self, transitionGeneration == generation {
                    takeShapeAtOnce(rest, topRadius: topRadius, bottomRadius: bottomRadius)
                }
                completion(generation)
            }
            return
        }
        let spring = HolzBarTheme.Motion.islandClose.delay(DesignTokens.Island.contentOutDuration)
        withAnimation(spring, completionCriteria: .removed) {
            widthAnimation = spring
            heightAnimation = spring
            contentAnimation = HolzBarTheme.Motion.islandContentOut
            contentShown = false
            centreX = rest.x + rest.width / 2
            width = rest.width
            height = rest.height
            self.topRadius = topRadius
            self.bottomRadius = bottomRadius
        } completion: {
            completion(generation)
        }
    }

    /// Moves the canvas, the panel's frame, at once and without animation. What is drawn keeps
    /// its place on the display.
    func moveCanvas(_ rect: NotchHubGeometry.Rect) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            canvas = rect
        }
    }

    /// Sets the shape and its radii at once, without animation.
    private func takeShapeAtOnce(_ shape: NotchHubGeometry.Rect, topRadius: Double, bottomRadius: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            centreX = shape.x + shape.width / 2
            width = shape.width
            height = shape.height
            self.topRadius = topRadius
            self.bottomRadius = bottomRadius
        }
    }
}
