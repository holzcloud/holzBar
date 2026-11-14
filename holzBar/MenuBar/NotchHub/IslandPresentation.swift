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
/// In the live state, while the hub is closed and something is live, the same shape is the notch
/// widened at menu bar height (``animateLive(to:reduceMotion:generation:completion:)``); the live
/// content is what ``IslandLiveView`` draws on it.
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

    /// What the live state shows: the board of the live activities and the widened shape's layout.
    /// While the hub is open the board is not kept up to date; it is set again when the hub
    /// closes into the live state.
    var liveBoard: HubActivityBoard.Board?
    var liveLayout: NotchHubGeometry.LiveLayout?

    /// Whether the live content is shown: it appears while the shape widens and leaves first.
    var showsLiveContent = false

    /// The animation of the next change of ``showsLiveContent``.
    var liveContentAnimation: Animation?

    /// Called when the live shape is clicked; the controller opens the hub.
    @ObservationIgnored var onLiveTap: (@MainActor () -> Void)?

    /// Whether the island takes the keyboard: the hotkey opened the hub.
    var takesKeyboard = false

    /// Counts the openings, so that the view says the context line once for each of them.
    var openingCount = 0

    /// Where the module row's top is, in display coordinates. It follows the layout when the hub
    /// opens, and the shape's lower edge when the height changes while the hub is open, so the row
    /// rides on the bottom edge as the shape springs.
    var moduleRowY: Double = 0

    /// The animation of the next change of the width (and the centre), of the height (and the
    /// radii), of the content and of the module row's place; `nil` means the change happens at
    /// once.
    var widthAnimation: Animation?
    var heightAnimation: Animation?
    var contentAnimation: Animation?
    var rowAnimation: Animation?

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
            showsLiveContent = false
            liveLayout = nil
            liveBoard = nil
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
        // A row that is already on screen (a hub that opens again while it closes) springs to its
        // new place; one that appears is placed at once.
        let rowMoves = self.layout != nil && !reduceMotion
        withAnimation(driver, completionCriteria: .removed) {
            self.layout = layout
            moduleRowY = layout.moduleRow.y
            rowAnimation = rowMoves ? HolzBarTheme.Motion.islandOpenHeight : nil
            widthAnimation = reduceMotion ? nil : HolzBarTheme.Motion.islandOpenWidth
            heightAnimation = reduceMotion ? nil : HolzBarTheme.Motion.islandOpenHeight
            contentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentIn
            // The live content, if it shows, leaves at once as the shape starts to grow.
            liveContentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentOut
            showsLiveContent = false
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

    /// Follows a change of the content's height while the hub is open (concept section 10b,
    /// "Motion"): the shape's lower edge takes the new layout with the opening's height spring, and
    /// the module row rides on it. The width and the radii stay as they are. With `reduceMotion` the
    /// height changes at once and the completion runs at once.
    ///
    /// `completion` runs once, with `generation`, when the shape has settled.
    func animateResize(
        to layout: NotchHubGeometry.IslandLayout,
        reduceMotion: Bool,
        generation: Int,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        transitionGeneration = generation
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.layout = layout
                moduleRowY = layout.moduleRow.y
                height = layout.shape.height
            }
            completion(generation)
            return
        }
        withAnimation(HolzBarTheme.Motion.islandOpenHeight, completionCriteria: .removed) {
            self.layout = layout
            heightAnimation = HolzBarTheme.Motion.islandOpenHeight
            rowAnimation = HolzBarTheme.Motion.islandOpenHeight
            moduleRowY = layout.moduleRow.y
            height = layout.shape.height
        } completion: {
            completion(generation)
        }
    }

    /// Closes the island into `rest`, the notch's rectangle or, while something is live, the live
    /// shape (concept section 10b); the radii are those of that shape. The content
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
                liveContentAnimation = HolzBarTheme.Motion.reduced
                showsLiveContent = false
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
            liveContentAnimation = HolzBarTheme.Motion.islandContentOut
            showsLiveContent = false
            centreX = rest.x + rest.width / 2
            width = rest.width
            height = rest.height
            self.topRadius = topRadius
            self.bottomRadius = bottomRadius
        } completion: {
            completion(generation)
        }
    }

    /// Widens the closed island to the live shape (concept section 10b, "Live state"): the width
    /// takes the opening's spring, the height is the top row's at once, so the shape never grows
    /// downward, and the live content appears with the content's curve. With `reduceMotion` the
    /// shape takes its target at once and the content fades.
    ///
    /// `completion` runs once, with `generation`, when the transition has settled.
    func animateLive(
        to live: NotchHubGeometry.LiveLayout,
        reduceMotion: Bool,
        generation: Int,
        completion: @escaping @MainActor (Int) -> Void
    ) {
        transitionGeneration = generation
        let driver = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandOpenWidth
        withAnimation(driver, completionCriteria: .removed) {
            liveLayout = live
            widthAnimation = reduceMotion ? nil : HolzBarTheme.Motion.islandOpenWidth
            heightAnimation = nil
            liveContentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentIn
            centreX = live.shape.x + live.shape.width / 2
            width = live.shape.width
            height = live.shape.height
            topRadius = DesignTokens.Island.liveTopRadius
            bottomRadius = DesignTokens.Island.liveBottomRadius
            showsLiveContent = true
        } completion: {
            completion(generation)
        }
    }

    /// Puts the island at the live shape at once, without animation, with the canvas the panel has.
    /// It is for a live shape that moves (another display, another menu bar height).
    func placeLive(_ live: NotchHubGeometry.LiveLayout, canvas: NotchHubGeometry.Rect) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.canvas = canvas
            liveLayout = live
            centreX = live.shape.x + live.shape.width / 2
            width = live.shape.width
            height = live.shape.height
            topRadius = DesignTokens.Island.liveTopRadius
            bottomRadius = DesignTokens.Island.liveBottomRadius
        }
    }

    /// The island has settled in the live shape: the parts of the open island are gone and the live
    /// content shows (it fades in when the island closed into the live shape).
    func settleLive(reduceMotion: Bool) {
        liveContentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentIn
        showsLiveContent = true
        layout = nil
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
