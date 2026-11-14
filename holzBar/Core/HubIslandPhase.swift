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

    /// Starts an animation towards a target, replacing any that runs.
    private static func starting(_ state: State, towards target: Target) -> State {
        var next = state
        next.target = target
        next.isAnimating = true
        next.generation += 1
        return next
    }
}
