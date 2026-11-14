//
//  TimerLiveActivities.swift
//  holzBar
//

import Foundation

nonisolated enum TimerLiveActivities {
    nonisolated struct Words: Equatable, Sendable {
        var running: String
        var done: String
    }

    static func activities(for board: TimerBoard, moduleID: String, words: Words) -> [LiveActivity] {
        []
    }
}
