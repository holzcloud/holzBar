//
//  HubStatusPills.swift
//  holzBar
//

import Foundation

/// Which status pill shows on which side of the notch in the open hub (concept section 10b,
/// "Status pills", decision D-02).
///
/// At most one pill shows on each side. On the left is the Timers module's own pill, which says
/// when the next timer ends. On the right is the first other live activity on the hub's board, by
/// the board's fixed order: a higher priority first (each activity's module gives it one), then the
/// newer start, then the key. The Timers module's own live activities never take the right pill,
/// because the left pill stands for them; every live activity that does not show on the right is
/// counted for the `+n` badge. There is no list of modules in this rule: the board's order is the
/// priority.
nonisolated enum HubStatusPills {
    /// The module whose pill is on the left of the notch.
    static let leftModuleID = "timers"

    /// What shows on each side.
    nonisolated struct Placement: Equatable, Sendable {
        /// The module whose pill shows on the left, or `nil` when it has none now.
        var left: String?
        /// The board of every live activity except the Timers module's.
        var rightBoard: HubActivityBoard.Board

        /// The activity that shows on the right, or `nil` when no other activity is live.
        var right: LiveActivity? {
            rightBoard.compact
        }

        /// How many other live activities do not show: the `+n` badge.
        var hiddenCount: Int {
            rightBoard.hiddenCount
        }
    }

    /// The placement at a moment: `pillModuleIDs` are the modules that have a pill now, and
    /// `activities` every live activity every module returned.
    static func place(pillModuleIDs: [String], activities: [LiveActivity], now: Date) -> Placement {
        Placement(
            left: pillModuleIDs.contains(leftModuleID) ? leftModuleID : nil,
            rightBoard: HubActivityBoard.board(activities.filter { $0.moduleID != leftModuleID }, now: now)
        )
    }
}
