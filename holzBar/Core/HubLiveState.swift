//
//  HubLiveState.swift
//  holzBar
//

import Foundation

nonisolated enum HubLiveState {
    nonisolated enum Trailing: Equatable, Sendable {
        case countdown(end: Date)
        case percent(Int)
        case word(String)
        case none
    }

    nonisolated struct Content: Equatable, Sendable {
        var symbol: String
        var tint: LiveActivityTint
        var trailing: Trailing
        var extraCount: Int
        var activityKey: String
    }

    static func make(board: HubActivityBoard.Board, now: Date) -> Content? {
        nil
    }
}
