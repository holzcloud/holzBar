//
//  TimersFormat.swift
//  holzBar
//

import Foundation

/// How the Timers module writes lengths, times and names. One place, so the tab, the tile and
/// the pill say the same.
enum TimersFormat {
    /// A length in words that fit a row, such as "5 min" or "1 hr, 30 min".
    static func length(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// A time of day in the user's format, such as "17:00".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A time left or elapsed, as clock digits, such as "4:32" or "1:05:00".
    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(min(seconds, 359_999).rounded(.down)))
        if whole >= 3_600 {
            return String(format: "%d:%02d:%02d", whole / 3_600, whole % 3_600 / 60, whole % 60)
        }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The last moment a stopwatch that started at `start` still counts.
    static func stopwatchEnd(from start: Date) -> Date {
        start.addingTimeInterval(TimerBoard.maximumElapsed)
    }

    /// What a timer is called: its label, else its length, else the moment it counts down to.
    static func name(of item: TimerItem) -> String {
        if !item.label.isEmpty {
            return item.label
        }
        switch item.kind {
        case .length(let seconds):
            return length(seconds)
        case .moment(let date):
            let at = time(date)
            return String(localized: "Until \(at)")
        case .stopwatch:
            return String(localized: "Stopwatch")
        }
    }
}
