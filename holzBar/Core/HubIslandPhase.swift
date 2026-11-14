//
//  HubIslandPhase.swift
//  holzBar
//

import Foundation

/// Stub for the RED run.
nonisolated enum HubIslandPhase {
    nonisolated enum Target: Int, Comparable, Sendable {
        case closed, live, open

        static func < (lhs: Target, rhs: Target) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    nonisolated struct State: Equatable, Sendable {
        var target = Target.closed
        var isAnimating = false
        var generation = 0
        var isLive = false

        var isOpen: Bool { false }
        var isPanelVisible: Bool { false }
        var hasShadow: Bool { false }
        var ordersOut: Bool { false }
        var showsContent: Bool { false }
        var showsLiveContent: Bool { false }
    }

    nonisolated enum Event: Equatable, Sendable {
        case open
        case close
        case resize
        case liveChanged(Bool)
        case animationFinished(generation: Int)
    }

    static func reduce(_ state: State, _ event: Event) -> State {
        state
    }
}
