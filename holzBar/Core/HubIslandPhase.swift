//
//  HubIslandPhase.swift
//  holzBar
//

import Foundation

/// What the Notch hub's panel does, as one pure state machine (concept section 10b).
///
/// The island opens, closes, resizes and, in the live state, sits widened at menu bar height.
/// Every one of those is an animation that ends by itself, and a new request can arrive while
/// one still runs. The reducer decides what the panel is at every moment, and a generation token
/// keeps a completion from an animation that was replaced from ever acting.
///
/// Rules, in order:
/// 1. A transition that starts an animation sets ``State/isAnimating`` and counts
///    ``State/generation`` up; its completion counts only with the generation that is current.
///    A completion with any other generation, or one that arrives when nothing animates, is
///    stale and changes nothing.
/// 2. `.open` heads for ``Target/open`` from closed, live and a closing alike (a turn around
///    while it is closing); while the target is already open it changes nothing.
/// 3. `.close` only acts on an open hub, and heads for ``Target/live`` while something is live,
///    else for ``Target/closed``. From the first frame of closing the hub is not open.
/// 4. `.resize` animates an open hub again; in any other target it changes nothing.
/// 5. `.liveChanged` always records the new answer. While the hub is open nothing else
///    happens; otherwise it moves a closed hub to live and a live one to closed, also while that
///    is only the target of a closing in progress.
/// 6. The panel is on screen while the target is not closed or while an animation runs. It
///    orders out only when a closing to closed has finished. It has its shadow only when the
///    open shape has settled.
/// 7. A completion that SwiftUI never reports is replaced by one timeout per transition
///    (``completionFallbackDelay``), which the owner feeds in as the same
///    ``Event/animationFinished(generation:)``; rule 1 makes it harmless when the real completion
///    came first or a newer transition has replaced the generation.
nonisolated enum HubIslandPhase {
    /// Where the island is, or is heading.
    nonisolated enum Target: Int, Comparable, Sendable {
        /// Nothing is drawn.
        case closed
        /// The notch widened at menu bar height.
        case live
        /// The open island.
        case open

        static func < (lhs: Target, rhs: Target) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// What the panel is at a moment.
    nonisolated struct State: Equatable, Sendable {
        /// Where the island is, or is heading.
        var target = Target.closed
        /// Whether an animation towards ``target`` still runs.
        var isAnimating = false
        /// Which animation counts: it goes up with every one that starts.
        var generation = 0
        /// Whether something is live, for the next close.
        var isLive = false

        /// Whether the hub is open, or opening. A closing hub is not open.
        var isOpen: Bool {
            target == .open
        }

        /// Whether the panel is on screen.
        var isPanelVisible: Bool {
            target != .closed || isAnimating
        }

        /// Whether the window's own shadow shows: only on the settled open shape.
        var hasShadow: Bool {
            target == .open && !isAnimating
        }

        /// Whether the panel has to be ordered out and emptied.
        var ordersOut: Bool {
            target == .closed && !isAnimating
        }
    }

    /// What can happen.
    nonisolated enum Event: Equatable, Sendable {
        case open
        case close
        case resize
        /// Whether something is live now.
        case liveChanged(Bool)
        /// An animation ended; it carries the generation it was started with.
        case animationFinished(generation: Int)
    }

    /// The state after an event.
    static func reduce(_ state: State, _ event: Event) -> State {
        switch event {
        case .open:
            guard state.target != .open else {
                return state
            }
            return starting(state, towards: .open)
        case .close:
            guard state.target == .open else {
                return state
            }
            return starting(state, towards: state.isLive ? .live : .closed)
        case .resize:
            guard state.target == .open else {
                return state
            }
            return starting(state, towards: .open)
        case .liveChanged(let isLive):
            guard isLive != state.isLive else {
                return state
            }
            var next = state
            next.isLive = isLive
            switch state.target {
            case .open:
                return next
            case .closed:
                return isLive ? starting(next, towards: .live) : next
            case .live:
                return isLive ? next : starting(next, towards: .closed)
            }
        case .animationFinished(let generation):
            guard state.isAnimating, generation == state.generation else {
                return state
            }
            var next = state
            next.isAnimating = false
            return next
        }
    }

    /// Whether going from one state to the next started a transition: an animation runs that
    /// has a generation the previous state did not have. The owner arms the fallback for it.
    static func startsTransition(from previous: State, to next: State) -> Bool {
        next.isAnimating && next.generation != previous.generation
    }

    /// The seconds a damped spring needs until its swing has fallen to `threshold` of the first
    /// one: `-ln(threshold) / (damping * 2π / response)`, the decay of its envelope. It is an
    /// upper bound for the time SwiftUI takes to report the spring as removed.
    static func settlingTime(response: Double, damping: Double, threshold: Double) -> Double {
        let rate = max(damping, 0.01) * 2 * Double.pi / max(response, 0.01)
        return -log(min(max(threshold, 1e-9), 0.999)) / rate
    }

    /// How long after a transition starts the fallback settles it when its animation has not
    /// reported the end: the longest motion of the island (the opening's two springs, the
    /// closing's spring after its delay, the content's curve after its delay) plus
    /// ``DesignTokens/Island/completionMargin``. One wait per transition; it never repeats.
    static let completionFallbackDelay: Double = {
        let island = DesignTokens.Island.self
        let threshold = island.settleThreshold
        let longest = max(
            settlingTime(response: island.openWidthResponse, damping: island.openWidthDamping, threshold: threshold),
            settlingTime(response: island.openHeightResponse, damping: island.openHeightDamping, threshold: threshold),
            island.contentOutDuration
                + settlingTime(response: island.closeResponse, damping: island.closeDamping, threshold: threshold),
            island.contentDelay + island.contentInDuration
        )
        return longest + island.completionMargin
    }()

    /// Starts an animation towards a target, replacing any that runs.
    private static func starting(_ state: State, towards target: Target) -> State {
        var next = state
        next.target = target
        next.isAnimating = true
        next.generation += 1
        return next
    }
}
