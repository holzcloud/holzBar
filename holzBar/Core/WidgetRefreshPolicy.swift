//
//  WidgetRefreshPolicy.swift
//  holzBar
//

import Foundation

/// How often the text of a widget changes, which decides what arms its timer (D-15).
nonisolated enum WidgetCadence: Equatable, Sendable {
    /// The text changes on an event only: a battery reading or a button.
    case eventOnly
    /// The text changes with the clock: at the next whole minute, or second.
    case clock(showsSeconds: Bool)
    /// The text changes when the minutes left change.
    case countdown(target: Date)
    /// The text is read again every `seconds`.
    case interval(seconds: Int, needsBaseline: Bool)

    init(definition: WidgetDefinition) {
        self = .eventOnly
    }
}

/// When a widget reads its source again, as a state machine that keeps timers away from
/// widgets nobody sees (D-14, D-15).
nonisolated struct WidgetRefreshPolicy: Equatable {
    nonisolated enum Event: Equatable, Sendable {
        case moduleEnabled(Bool)
        case shown(Bool)
        case paused(Bool)
        case lowPowerMode(Bool)
        case timerFired
        case clockChanged
        case sourceChanged
        case cadenceChanged(WidgetCadence)
    }

    nonisolated enum TimerChange: Equatable, Sendable {
        case keep
        case cancel
        case arm(ContinuousClock.Instant, tolerance: Duration)
    }

    nonisolated struct Command: Equatable, Sendable {
        var refreshes = false
        var timer = TimerChange.keep
        var marksUnavailable = false

        static let unchanged = Command()
    }

    nonisolated struct Fire: Equatable, Sendable {
        var delay: Duration
        var tolerance: Duration
    }

    private(set) var cadence: WidgetCadence
    private(set) var isModuleEnabled = true
    private(set) var isShown = false
    private(set) var isPaused = false
    private(set) var settlesAt: ContinuousClock.Instant?
    private(set) var isLowPowerMode = false
    private(set) var awaitsSecondSample = false

    var isVisible: Bool {
        false
    }

    init(cadence: WidgetCadence) {
        self.cadence = cadence
    }

    mutating func handle(
        _ event: Event,
        at now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        .unchanged
    }

    static func nextFire(
        for cadence: WidgetCadence,
        date: Date,
        calendar: Calendar,
        isLowPowerMode: Bool
    ) -> Fire? {
        nil
    }
}
