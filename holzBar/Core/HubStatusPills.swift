//
//  HubStatusPills.swift
//  holzBar
//

import Foundation

/// Which status pill shows on which side of the notch in the open hub.
nonisolated enum HubStatusPills {
    static let leftModuleID = "timers"

    nonisolated struct Placement: Equatable, Sendable {
        var left: String?
        var rightBoard: HubActivityBoard.Board
        var right: LiveActivity? { nil }
        var hiddenCount: Int { 0 }
    }

    static func place(pillModuleIDs: [String], activities: [LiveActivity], now: Date) -> Placement {
        Placement(left: nil, rightBoard: HubActivityBoard.board([], now: now))
    }
}
