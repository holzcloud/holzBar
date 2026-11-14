//
//  TimerLiveActivities.swift
//  holzBar
//

import Foundation

/// Which timers of a ``TimerBoard`` are live activities, and what each one says (D-05, the
/// Timers module's rules).
///
/// A running timer is one activity: symbol `timer`, amber, its end as the countdown the system
/// draws, priority 15 (between a download's 10 and a camera's 20). A timer that has ended is one
/// activity for ``HubActivityBoard/finishedHold`` seconds, worded "Done". A paused timer and a
/// stopwatch, counting or halted, are not live. The timer's label goes to the ``LiveActivity/detail``
/// only, which neither the widened notch nor the open hub's right pill draws; it never reaches the
/// title, the symbol or the short word. Core cannot localize, so the words are passed in. The
/// function reads only the board it is given: it starts nothing and waits for nothing.
nonisolated enum TimerLiveActivities {
    /// The priority of a timer's activity.
    static let priority = 15

    /// The plain words an activity carries; never the timer's label.
    nonisolated struct Words: Equatable, Sendable {
        /// The title of a running timer, such as "Timer".
        var running: String
        /// The title and the short word of a timer that has ended, such as "Done".
        var done: String
    }

    /// The live activities of a board, in the board's order, one per running or finished timer.
    static func activities(for board: TimerBoard, moduleID: String, words: Words) -> [LiveActivity] {
        board.items.compactMap { item in
            let detail = item.label.isEmpty ? nil : item.label
            switch item.state {
            case let .running(start, end):
                return LiveActivity(
                    id: item.id.uuidString,
                    moduleID: moduleID,
                    kind: .timer,
                    symbol: "timer",
                    title: words.running,
                    detail: detail,
                    priority: priority,
                    startedAt: start,
                    endsAt: end,
                    tint: .amber
                )
            case let .finished(at):
                return LiveActivity(
                    id: item.id.uuidString,
                    moduleID: moduleID,
                    kind: .timer,
                    symbol: "timer",
                    title: words.done,
                    detail: detail,
                    priority: priority,
                    startedAt: at,
                    finishedAt: at,
                    tint: .amber,
                    compactValue: words.done
                )
            case .paused, .counting, .halted:
                return nil
            }
        }
    }
}
