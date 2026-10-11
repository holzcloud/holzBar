//
//  WidgetRefreshPolicy.swift
//  holzBar
//

import Foundation

/// How often the text of a widget changes, which decides what arms its timer (D-15).
nonisolated enum WidgetCadence: Equatable, Sendable {
    /// The text changes on an event only: a battery reading, or a button. No timer is ever armed.
    case eventOnly
    /// The text changes with the clock: at the next whole minute, or at the next whole second
    /// when it shows seconds.
    case clock(showsSeconds: Bool)
    /// The text changes when the minutes left change, and never after the moment has passed.
    case countdown(target: Date)
    /// The text is read again every `seconds`. A source that is a rate between two readings
    /// (CPU load) needs a baseline reading before its first value.
    case interval(seconds: Int, needsBaseline: Bool)

    /// The seconds between two readings of the uptime.
    static let uptimeSeconds = 60
    /// The seconds between two readings of the free disk space.
    static let freeDiskSeconds = 300

    /// The cadence of a widget: its kind and source, and the interval the user tuned.
    ///
    /// A button never changes its text, a countdown without a moment has nothing to count, and
    /// the tuned interval of CPU and memory is kept inside its range even when the definition was
    /// not validated.
    init(definition: WidgetDefinition) {
        guard definition.kind == .text else {
            self = .eventOnly
            return
        }
        switch definition.source {
        case .dateTime:
            self = .clock(showsSeconds: definition.showsSeconds)
        case .battery:
            self = .eventOnly
        case .cpu:
            self = .interval(seconds: Self.tunedSeconds(definition, for: .cpu), needsBaseline: true)
        case .memory:
            self = .interval(seconds: Self.tunedSeconds(definition, for: .memory), needsBaseline: false)
        case .uptime:
            self = .interval(seconds: Self.uptimeSeconds, needsBaseline: false)
        case .freeDisk:
            self = .interval(seconds: Self.freeDiskSeconds, needsBaseline: false)
        case .countdown:
            if let target = definition.countdownTarget {
                self = .countdown(target: target)
            } else {
                self = .eventOnly
            }
        }
    }

    private static func tunedSeconds(_ definition: WidgetDefinition, for source: WidgetSource) -> Int {
        guard let range = source.refreshRange else {
            return source.defaultRefreshSeconds ?? uptimeSeconds
        }
        let seconds = definition.refreshSeconds ?? source.defaultRefreshSeconds ?? range.lowerBound
        return min(max(seconds, range.lowerBound), range.upperBound)
    }
}

/// When one widget reads its source again: a pure state machine that keeps timers away from a
/// widget nobody sees (D-14, D-15).
///
/// A widget is visible when the module is on, its section is shown and the Mac is in use. While
/// it is not, no timer exists and its text is marked unavailable; when it becomes visible it
/// reads once and arms the next change. After a lock, a sleep or a switch of the login session
/// ends, the policy waits ``SystemActivity/settleDelay`` before it reads, as the menu bar does.
///
/// The policy observes nothing. The host feeds it events, with the instant of each (as
/// ``SystemActivity`` is fed), the paused flag from `SystemActivityMonitor` among them, and does
/// what the returned ``Command`` says: read, arm or cancel one timer, mark the text. That keeps
/// every rule testable with a fake clock.
nonisolated struct WidgetRefreshPolicy: Equatable {
    /// Something that changes what the widget has to do.
    nonisolated enum Event: Equatable, Sendable {
        /// The widgets module is switched on or off.
        case moduleEnabled(Bool)
        /// The widget's section is shown or hidden.
        case shown(Bool)
        /// The Mac is not in use (`SystemActivity.isPaused`).
        case paused(Bool)
        /// Low Power Mode is switched on or off.
        case lowPowerMode(Bool)
        /// The timer the policy armed fired.
        case timerFired
        /// The system clock, time zone or day changed.
        case clockChanged
        /// The source announced a change (a power source event).
        case sourceChanged
        /// The user changed what the widget shows.
        case cadenceChanged(WidgetCadence)
    }

    /// What the host does with the widget's one timer.
    nonisolated enum TimerChange: Equatable, Sendable {
        /// Leave the timer as it is.
        case keep
        /// Cancel the timer; none is armed.
        case cancel
        /// Replace the timer with a one-shot at the instant, with the given tolerance.
        case arm(ContinuousClock.Instant, tolerance: Duration)
    }

    /// What the host does after an event.
    nonisolated struct Command: Equatable, Sendable {
        /// Read the source once and show the text.
        var refreshes = false
        /// What happens to the timer.
        var timer = TimerChange.keep
        /// Show the text as unavailable until the next reading.
        var marksUnavailable = false

        /// Nothing to do.
        static let unchanged = Command()
    }

    /// When the next timer fires: the delay and the tolerance the system may add.
    nonisolated struct Fire: Equatable, Sendable {
        var delay: Duration
        var tolerance: Duration
    }

    /// No timer is armed sooner than this after the event that arms it, so a boundary that is
    /// almost reached never makes a tight loop.
    static let minimumDelay = Duration.milliseconds(250)
    /// How far after a minute or second boundary the clock reads, so the text shows the new
    /// value and not the old one.
    static let boundaryMargin = 50
    /// How long after a reveal a rate source (CPU) takes its second sample.
    static let secondSampleDelay = Duration.seconds(1)
    /// The longest interval a stored cadence is armed with, in seconds (a day). A stored value
    /// beyond it, or one that would overflow when doubled, is brought down to it.
    static let maximumIntervalSeconds = 86_400

    /// What the widget shows and how often it changes.
    private(set) var cadence: WidgetCadence
    /// Whether the widgets module is on.
    private(set) var isModuleEnabled = true
    /// Whether the widget's section is shown.
    private(set) var isShown = false
    /// Whether the Mac is not in use: locked, asleep or another session in front.
    private(set) var isPaused = false
    /// When the menu bar has settled after the Mac was in use again; `nil` when it has.
    private(set) var settlesAt: ContinuousClock.Instant?
    /// Whether Low Power Mode is on.
    private(set) var isLowPowerMode = false
    /// Whether a rate source waits for its second sample, one second after the reveal.
    private(set) var awaitsSecondSample = false

    /// Whether the widget is seen and read: the module is on, the section is shown, the Mac is in
    /// use and the menu bar has settled (D-14).
    var isVisible: Bool {
        isActive && settlesAt == nil
    }

    /// Whether the widget could be seen once the menu bar settles.
    private var isActive: Bool {
        isModuleEnabled && isShown && !isPaused
    }

    /// A policy for a widget that is not shown yet. The host feeds it `shown(true)` when the
    /// widget's section is shown, and `paused(true)` first when the Mac is not in use.
    init(cadence: WidgetCadence) {
        self.cadence = cadence
    }

    /// Takes in an event and says what the host does.
    ///
    /// - Parameters:
    ///   - event: What happened.
    ///   - now: The instant it happened, on the clock the timer runs on.
    ///   - date: The wall-clock time of it, for the clock and the countdown.
    ///   - calendar: The calendar the clock's minutes and seconds are counted in.
    mutating func handle(
        _ event: Event,
        at now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        let wasActive = isActive
        switch event {
        case .moduleEnabled(let isEnabled):
            isModuleEnabled = isEnabled
            return settle(wasActive: wasActive, turnedOff: !isEnabled, now: now, date: date, calendar: calendar)
        case .shown(let isShown):
            self.isShown = isShown
            return settle(wasActive: wasActive, turnedOff: false, now: now, date: date, calendar: calendar)
        case .paused(let isPaused):
            if isPaused {
                self.isPaused = true
                settlesAt = nil
            } else if self.isPaused {
                self.isPaused = false
                settlesAt = now + SystemActivity.settleDelay
            }
            return settle(wasActive: wasActive, turnedOff: false, now: now, date: date, calendar: calendar)
        case .lowPowerMode(let isOn):
            return changeLowPowerMode(isOn, now: now, date: date, calendar: calendar)
        case .timerFired:
            return fireTimer(now: now, date: date, calendar: calendar)
        case .clockChanged:
            guard isVisible else {
                return .unchanged
            }
            return refreshAndArm(reveal: false, now: now, date: date, calendar: calendar)
        case .sourceChanged:
            guard isVisible, cadence == .eventOnly else {
                return .unchanged
            }
            return Command(refreshes: true)
        case .cadenceChanged(let newCadence):
            return change(to: newCadence, now: now, date: date, calendar: calendar)
        }
    }

    /// The delay and tolerance of the timer for a cadence, or `nil` when none is armed: the
    /// source changes on events only, or the countdown has passed (D-15).
    ///
    /// - The clock fires at the next whole minute (second), plus 50 ms, with a tolerance of a
    ///   tenth of the minute (second).
    /// - A countdown fires when the minutes left change, with a tolerance of 6 s.
    /// - A polling interval fires at its interval, doubled in Low Power Mode, with a tolerance
    ///   of a tenth of the interval.
    /// - Nothing fires sooner than 250 ms (``minimumDelay``).
    static func nextFire(
        for cadence: WidgetCadence,
        date: Date,
        calendar: Calendar,
        isLowPowerMode: Bool
    ) -> Fire? {
        switch cadence {
        case .eventOnly:
            return nil
        case .clock(let showsSeconds):
            let component: Calendar.Component = showsSeconds ? .second : .minute
            let period = showsSeconds ? 1 : 60
            var milliseconds = period * 1_000
            if let boundary = calendar.dateInterval(of: component, for: date)?.end {
                milliseconds = ceiledMilliseconds(boundary.timeIntervalSince(date), limit: period * 1_000)
            }
            return fire(afterMilliseconds: milliseconds + boundaryMargin, interval: .seconds(period))
        case .countdown(let target):
            let remaining = Countdown.remaining(now: date, target: target)
            guard let seconds = Countdown.secondsToNextChange(remaining: remaining) else {
                return nil
            }
            let milliseconds = ceiledMilliseconds(seconds, limit: 60_000)
            return fire(afterMilliseconds: milliseconds + boundaryMargin, interval: .seconds(60))
        case .interval(let seconds, _):
            let clamped = min(max(seconds, 1), maximumIntervalSeconds) * (isLowPowerMode ? 2 : 1)
            return fire(afterMilliseconds: clamped * 1_000, interval: .seconds(clamped))
        }
    }

    // MARK: Rules

    /// The command after the module, the section or the Mac's use changed.
    private mutating func settle(
        wasActive: Bool,
        turnedOff: Bool,
        now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        guard isActive else {
            awaitsSecondSample = false
            guard wasActive || turnedOff else {
                return .unchanged
            }
            return Command(refreshes: false, timer: .cancel, marksUnavailable: true)
        }
        guard !wasActive else {
            return .unchanged
        }
        // It became active. Inside the settle wait only the settle timer is armed; after it, the
        // widget reads at once.
        if let settlesAt, now < settlesAt {
            return Command(timer: .arm(settlesAt, tolerance: SystemActivity.settleDelay / 10))
        }
        settlesAt = nil
        return refreshAndArm(reveal: true, now: now, date: date, calendar: calendar)
    }

    private mutating func fireTimer(now: ContinuousClock.Instant, date: Date, calendar: Calendar) -> Command {
        // A timer that still fires while the widget is hidden, locked or off refreshes nothing and
        // arms nothing.
        guard isActive else {
            return Command(refreshes: false, timer: .cancel, marksUnavailable: false)
        }
        if let settlesAt {
            guard now >= settlesAt else {
                // Early: wait for the end of the settle wait.
                return Command(timer: .arm(settlesAt, tolerance: SystemActivity.settleDelay / 10))
            }
            self.settlesAt = nil
            return refreshAndArm(reveal: true, now: now, date: date, calendar: calendar)
        }
        return refreshAndArm(reveal: false, now: now, date: date, calendar: calendar)
    }

    private mutating func changeLowPowerMode(
        _ isOn: Bool,
        now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        guard isOn != isLowPowerMode else {
            return .unchanged
        }
        isLowPowerMode = isOn
        // Only a polling interval depends on it; the second sample after a reveal keeps its time.
        guard isVisible, case .interval = cadence, !awaitsSecondSample else {
            return .unchanged
        }
        return Command(timer: timerChange(now: now, date: date, calendar: calendar))
    }

    private mutating func change(
        to newCadence: WidgetCadence,
        now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        guard newCadence != cadence else {
            return .unchanged
        }
        cadence = newCadence
        awaitsSecondSample = false
        // Not visible: nothing is armed; the reveal, or the end of the settle wait, uses it.
        guard isVisible else {
            return .unchanged
        }
        return refreshAndArm(reveal: true, now: now, date: date, calendar: calendar)
    }

    /// Reads once and arms the next change. After a reveal a rate source arms its second sample
    /// first, because one reading alone is a baseline and has no value.
    private mutating func refreshAndArm(
        reveal: Bool,
        now: ContinuousClock.Instant,
        date: Date,
        calendar: Calendar
    ) -> Command {
        awaitsSecondSample = false
        if reveal, case .interval(seconds: _, needsBaseline: true) = cadence {
            awaitsSecondSample = true
            let timer = TimerChange.arm(now + Self.secondSampleDelay, tolerance: Self.secondSampleDelay / 10)
            return Command(refreshes: true, timer: timer)
        }
        return Command(refreshes: true, timer: timerChange(now: now, date: date, calendar: calendar))
    }

    private func timerChange(now: ContinuousClock.Instant, date: Date, calendar: Calendar) -> TimerChange {
        let fire = Self.nextFire(for: cadence, date: date, calendar: calendar, isLowPowerMode: isLowPowerMode)
        guard let fire else {
            return .cancel
        }
        return .arm(now + fire.delay, tolerance: fire.tolerance)
    }

    // MARK: Arithmetic

    /// A fire after `milliseconds`, never sooner than ``minimumDelay``, with a tolerance of a
    /// tenth of the `interval` the timer repeats at.
    private static func fire(afterMilliseconds milliseconds: Int, interval: Duration) -> Fire {
        Fire(delay: max(.milliseconds(milliseconds), minimumDelay), tolerance: interval / 10)
    }

    /// Whole milliseconds, rounded up, of a number of seconds that is at most `limit`; zero for a
    /// number that is not finite or not positive.
    private static func ceiledMilliseconds(_ seconds: Double, limit: Int) -> Int {
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return min(Int((seconds * 1_000).rounded(.up)), limit)
    }
}
