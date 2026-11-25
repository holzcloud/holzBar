//
//  ThresholdEvaluator.swift
//  holzBar
//

import Foundation

/// One reading, as an alert rule sees it. A reading that is missing or does not fit the rule's
/// signal is ``unavailable`` or is ignored: it advances no timer, fires nothing and clears nothing.
nonisolated enum AlertObservation: Equatable, Sendable {
    /// The CPU load as a fraction of 0 to 1.
    case fraction(Double)
    /// The memory pressure level.
    case pressure(ReadoutPressure)
    /// The thermal state.
    case thermal(ReadoutThermal)
    /// The free space of the startup volume, in bytes.
    case freeBytes(Int64)
    /// The Mac battery: the system's whole percent and whether the Mac runs on battery power.
    case battery(percent: Int, onBattery: Bool)
    /// The read failed or the Mac has nothing to read.
    case unavailable
}

/// Where an observation lies relative to a rule, named by the rule's condition and not by a
/// direction, because free disk space and the Mac battery fire below their threshold.
///
/// Each numeric signal is a Schmitt trigger: it enters at the threshold and leaves only past an
/// exit margin, so a value hovering around the threshold neither fires nor clears again and again
/// (ALRT-04). A level signal has no band.
nonisolated enum AlertZone: Equatable, Sendable {
    case firing, between, recovered, unplugged

    /// The zone of an observation under a rule; `nil` for an unavailable observation, one that does
    /// not fit the rule's signal, or an impossible value.
    ///
    /// - CPU load: `firing` above the threshold (90 % is not above 90), `recovered` below the
    ///   threshold minus ``ThresholdEvaluator/Tuning/percentMargin``, `between` in between.
    /// - Free disk space: `firing` below the threshold, `recovered` at the threshold plus the
    ///   larger of ``ThresholdEvaluator/Tuning/diskMarginMinimumBytes`` and a tenth of the
    ///   threshold, `between` in between.
    /// - Mac battery: `unplugged` when not on battery power (plugging in clears the alert, D-14),
    ///   else `firing` below the threshold, `recovered` at the threshold plus the margin.
    /// - A level: `firing` at or above the rule's level, otherwise `recovered`.
    static func zone(of observation: AlertObservation, rule: ThresholdRule) -> AlertZone? {
        switch (rule.signal, observation) {
        case (.cpu, .fraction(let fraction)):
            guard let percent = cpuPercent(fraction) else {
                return nil
            }
            if percent > rule.limit {
                return .firing
            }
            return percent < rule.limit - ThresholdEvaluator.Tuning.percentMargin ? .recovered : .between
        case (.memoryPressure, .pressure(let pressure)):
            return pressure >= rule.pressureLevel ? .firing : .recovered
        case (.thermal, .thermal(let state)):
            return state >= rule.thermalLevel ? .firing : .recovered
        case (.freeDisk, .freeBytes(let bytes)):
            guard bytes >= 0 else {
                return nil
            }
            let threshold = rule.thresholdBytes
            if bytes < threshold {
                return .firing
            }
            let margin = max(
                ThresholdEvaluator.Tuning.diskMarginMinimumBytes,
                threshold / ThresholdEvaluator.Tuning.diskMarginDivisor
            )
            return bytes >= threshold + margin ? .recovered : .between
        case (.macBattery, .battery(let percent, let onBattery)):
            guard (0...100).contains(percent) else {
                return nil
            }
            guard onBattery else {
                return .unplugged
            }
            if percent < rule.limit {
                return .firing
            }
            return percent >= rule.limit + ThresholdEvaluator.Tuning.percentMargin ? .recovered : .between
        default:
            return nil
        }
    }

    /// The CPU load as one whole percent, rounded half away from zero and clamped to 0 to 100; `nil`
    /// for a load that is not finite. The rule compares this number and the alert shows it.
    static func cpuPercent(_ fraction: Double) -> Int? {
        guard fraction.isFinite else {
            return nil
        }
        let percent = (fraction * 100).rounded()
        return Int(min(max(percent, 0), 100))
    }
}

/// An alert as it stands: its signal, its severity and the latest value.
nonisolated struct AlertSnapshot: Equatable, Sendable {
    var signal: AlertSignal
    var severity: AlertSeverity
    var observation: AlertObservation
}

/// The state machine that decides when an alert fires and when it clears (D-13 to D-15, ALRT-01,
/// ALRT-04).
///
/// A pure value: the host passes the instants (from `SuspendingClock`, so a sleep adds nothing to a
/// hold) and the readings, and acts on the returned ``Effect`` values. Per rule: a reading in the
/// `firing` zone starts a hold; when the hold has run out the alert fires; once the reading has
/// been past the exit for ``Tuning/clearHold`` the alert clears. A reading in between neither
/// starts nor ends anything.
nonisolated struct ThresholdEvaluator: Sendable {
    /// The fixed numbers of the anti-flap rules (D-15). They are not settings; one sentence in the
    /// module's info popover explains them.
    nonisolated enum Tuning {
        /// How far past the threshold a CPU or battery reading must go to leave its band: five
        /// points, the margin of ``AccessoryLowBatteryGate``, larger than the jitter of two
        /// readings of the CPU load.
        static let percentMargin = AccessoryLowBatteryGate.hysteresis
        /// The smallest exit margin of free disk space; a flat five points means nothing for bytes.
        static let diskMarginMinimumBytes: Int64 = 1_000_000_000
        /// The exit margin of free disk space is the threshold divided by this, when that is more.
        static let diskMarginDivisor: Int64 = 10
        /// How long a reading must stay past the exit before the alert clears or a running hold is
        /// dropped: longer than two readings at the slowest alert cadence (10 s, 20 s in Low Power
        /// Mode), short enough that "done" is not late.
        static let clearHold = Duration.seconds(30)
        /// The least time between two fires of the same rule (D-15), counted from the last fire. A
        /// value that stays past the threshold is told once per half hour at most, and the clock
        /// that counts it pauses in sleep, which only makes it quieter.
        static let cooldown = Duration.seconds(1800)
        /// How many alerts may fire inside ``rateCapWindow``, over all rules (D-15): five rules
        /// and a cap of four mean a bad hour is never more than about one alert per quarter hour.
        static let rateCapCount = 4
        /// The rolling window of the rate cap.
        static let rateCapWindow = Duration.seconds(3600)
        /// How long nothing fires after a wake, a display change, enabling a rule or starting the
        /// module (ALRT-04): the first readings after such a change are not a reason to alert. It
        /// equals the clear hold, so one number explains both.
        static let quietPeriod = Duration.seconds(30)
    }

    /// What the host does after a call.
    nonisolated enum Effect: Equatable, Sendable {
        /// A new alert: the host shows the activity and delivers the notification.
        case fired(AlertSnapshot)
        /// The value or the severity of a firing alert changed: the host updates the activity only.
        case updated(AlertSnapshot)
        /// The condition is gone: the host finishes the activity with the done hold and removes
        /// the notification.
        case cleared(AlertSignal)
        /// The alert ends without a done hold: the rule or the module was switched off, the
        /// threshold no longer holds, or the Mac rests.
        case ended(AlertSignal)
    }

    private nonisolated enum Phase: Sendable {
        /// A hold is running since `start`; `recoveredSince` is when the reading went past the exit.
        case pending(start: SuspendingClock.Instant, recoveredSince: SuspendingClock.Instant?)
        /// The alert is on; `recoveredSince` is when the reading went past the exit.
        case firing(snapshot: AlertSnapshot, recoveredSince: SuspendingClock.Instant?)
    }

    private var rules: [AlertSignal: ThresholdRule] = [:]
    private var phases: [AlertSignal: Phase] = [:]
    private var latest: [AlertSignal: AlertObservation] = [:]
    /// Until when nothing fires for a signal (a wake, a display change, enabling the rule).
    private var quietEnds: [AlertSignal: SuspendingClock.Instant] = [:]
    /// When each signal last fired, for the cooldown. A rest does not forget it.
    private var lastFires: [AlertSignal: SuspendingClock.Instant] = [:]
    /// The fires of the last ``Tuning/rateCapWindow``, oldest first. A rest does not forget them.
    private var fires: [SuspendingClock.Instant] = []

    /// The alerts that are on now, by signal.
    var firing: [AlertSignal: AlertSnapshot] {
        phases.compactMapValues { phase in
            if case .firing(let snapshot, _) = phase {
                snapshot
            } else {
                nil
            }
        }
    }

    /// Takes the rules in force and says what changes at once.
    ///
    /// A rule that went on is quiet for ``Tuning/quietPeriod`` (the first configuration counts);
    /// one that went off ends its alert with no done hold; one whose threshold, level or hold
    /// changed is judged again on its latest reading under the same rules: a firing alert whose
    /// reading is now past the new exit ends, a running hold keeps its start.
    mutating func configure(_ newRules: [ThresholdRule], at now: SuspendingClock.Instant) -> [Effect] {
        var effects: [Effect] = []
        for signal in AlertSignal.allCases {
            let proposed = newRules.first { $0.signal == signal }?.validated
            let new = proposed?.isOn == true ? proposed : nil
            let old = rules[signal]
            rules[signal] = new
            switch (old, new) {
            case (nil, nil):
                continue
            case (nil, _?):
                let end = now + Tuning.quietPeriod
                quietEnds[signal] = max(quietEnds[signal] ?? end, end)
                phases[signal] = nil
                latest[signal] = nil
            case (_?, nil):
                if case .firing? = phases[signal] {
                    effects.append(.ended(signal))
                }
                phases[signal] = nil
                latest[signal] = nil
            case (let old?, let new?):
                guard old != new else {
                    continue
                }
                effects += reevaluate(signal, rule: new, at: now)
            }
        }
        return effects
    }

    /// Takes one reading of a signal.
    mutating func observe(
        _ observation: AlertObservation,
        for signal: AlertSignal,
        at now: SuspendingClock.Instant
    ) -> [Effect] {
        guard let rule = rules[signal], let zone = AlertZone.zone(of: observation, rule: rule) else {
            return []
        }
        // Time passes first: a deadline that came before this reading is judged on what was known.
        var effects = step(signal, at: now)
        latest[signal] = observation
        switch zone {
        case .unplugged:
            if case .firing? = phases[signal] {
                effects.append(.cleared(signal))
            }
            phases[signal] = nil
            return effects
        case .firing:
            switch phases[signal] {
            case nil:
                phases[signal] = .pending(start: now, recoveredSince: nil)
            case .pending(let start, _)?:
                phases[signal] = .pending(start: start, recoveredSince: nil)
            case .firing(let snapshot, _)?:
                phases[signal] = .firing(snapshot: snapshot, recoveredSince: nil)
            }
        case .between:
            switch phases[signal] {
            case .pending(let start, _)?:
                phases[signal] = .pending(start: start, recoveredSince: nil)
            case .firing(let snapshot, _)?:
                phases[signal] = .firing(snapshot: snapshot, recoveredSince: nil)
            case nil:
                break
            }
        case .recovered:
            switch phases[signal] {
            case .pending(let start, let since)?:
                phases[signal] = .pending(start: start, recoveredSince: since ?? now)
            case .firing(let snapshot, let since)?:
                phases[signal] = .firing(snapshot: snapshot, recoveredSince: since ?? now)
            case nil:
                break
            }
        }
        effects += refresh(signal, rule: rule, observation: observation)
        effects += step(signal, at: now)
        return effects
    }

    /// The Mac rests (sleep, screen sleep, lock, session switch): every firing alert ends with no
    /// done hold, every running hold is dropped and the latest readings are forgotten. The cooldown
    /// and the rate-cap history stay, so a sleep and a wake never create a fire of their own.
    mutating func rest(at now: SuspendingClock.Instant) -> [Effect] {
        var effects: [Effect] = []
        for signal in AlertSignal.allCases {
            if case .firing? = phases[signal] {
                effects.append(.ended(signal))
            }
        }
        phases.removeAll()
        latest.removeAll()
        return effects
    }

    /// The Mac is in use again, or the displays changed: nothing fires for ``Tuning/quietPeriod``.
    /// A fire that is due meanwhile is deferred to the end of the quiet period, not dropped.
    mutating func resume(at now: SuspendingClock.Instant) {
        let end = now + Tuning.quietPeriod
        for signal in AlertSignal.allCases {
            quietEnds[signal] = max(quietEnds[signal] ?? end, end)
        }
    }

    /// Lets time pass to `now`: every hold that has run out fires, every clear hold that has run
    /// out clears. Effects come in the order of ``AlertSignal/allCases``.
    mutating func advance(to now: SuspendingClock.Instant) -> [Effect] {
        var effects: [Effect] = []
        for signal in AlertSignal.allCases {
            effects += step(signal, at: now)
        }
        return effects
    }

    /// The next instant at which ``advance(to:)`` has something to do, or `nil` when no alert is
    /// pending or on a clear hold.
    func nextDeadline() -> SuspendingClock.Instant? {
        var deadlines: [SuspendingClock.Instant] = []
        for signal in AlertSignal.allCases {
            switch phases[signal] {
            case .pending(let start, let since)?:
                if let since {
                    deadlines.append(since + Tuning.clearHold)
                } else {
                    deadlines.append(earliestFire(signal, start: start))
                }
            case .firing(_, let since?)?:
                deadlines.append(since + Tuning.clearHold)
            case .firing(_, nil)?, nil:
                break
            }
        }
        return deadlines.min()
    }

    // MARK: Steps

    /// The earliest instant a pending alert may fire: when its hold has run out and no block is
    /// left (the quiet period, the cooldown, the rate cap). A blocked fire waits for this instant
    /// and happens then if the value has not recovered; it is never dropped.
    private func earliestFire(_ signal: AlertSignal, start: SuspendingClock.Instant) -> SuspendingClock.Instant {
        var candidate = start + (rules[signal]?.hold.duration ?? .zero)
        if let quiet = quietEnds[signal] {
            candidate = max(candidate, quiet)
        }
        if let last = lastFires[signal] {
            candidate = max(candidate, last + Tuning.cooldown)
        }
        return max(candidate, rateCapEnd(at: candidate))
    }

    /// The fires that still count against the rate cap at `instant`.
    private func recentFires(at instant: SuspendingClock.Instant) -> [SuspendingClock.Instant] {
        fires.filter { $0 + Tuning.rateCapWindow > instant }
    }

    /// When the rate cap lets another alert fire, if it blocks at `instant`: an hour after the
    /// oldest of the last four fires.
    private func rateCapEnd(at instant: SuspendingClock.Instant) -> SuspendingClock.Instant {
        let recent = recentFires(at: instant)
        guard recent.count >= Tuning.rateCapCount else {
            return instant
        }
        return recent[recent.count - Tuning.rateCapCount] + Tuning.rateCapWindow
    }

    /// Whether a pending alert may fire at `now`, judged on the fires of this very moment.
    private func canFire(_ signal: AlertSignal, start: SuspendingClock.Instant, at now: SuspendingClock.Instant) -> Bool {
        guard now >= start + (rules[signal]?.hold.duration ?? .zero),
              now >= (quietEnds[signal] ?? now),
              now >= (lastFires[signal].map { $0 + Tuning.cooldown } ?? now)
        else {
            return false
        }
        return recentFires(at: now).count < Tuning.rateCapCount
    }

    /// The time-based steps of one signal at `now`.
    private mutating func step(_ signal: AlertSignal, at now: SuspendingClock.Instant) -> [Effect] {
        switch phases[signal] {
        case .pending(let start, let since)?:
            if let since {
                if now - since >= Tuning.clearHold {
                    phases[signal] = nil
                }
                return []
            }
            guard canFire(signal, start: start, at: now) else {
                return []
            }
            guard let rule = rules[signal], let observation = latest[signal] else {
                phases[signal] = nil
                return []
            }
            let snapshot = AlertSnapshot(
                signal: signal,
                severity: AlertSeverity.of(observation, rule: rule),
                observation: observation
            )
            phases[signal] = .firing(snapshot: snapshot, recoveredSince: nil)
            lastFires[signal] = now
            fires.removeAll { $0 + Tuning.rateCapWindow <= now }
            fires.append(now)
            return [.fired(snapshot)]
        case .firing(_, let since?)?:
            guard now - since >= Tuning.clearHold else {
                return []
            }
            phases[signal] = nil
            return [.cleared(signal)]
        case .firing(_, nil)?, nil:
            return []
        }
    }

    /// A rule changed while it stays on: judges its latest reading again under the new rule.
    private mutating func reevaluate(
        _ signal: AlertSignal,
        rule: ThresholdRule,
        at now: SuspendingClock.Instant
    ) -> [Effect] {
        guard let observation = latest[signal], let zone = AlertZone.zone(of: observation, rule: rule) else {
            return step(signal, at: now)
        }
        var effects: [Effect] = []
        switch phases[signal] {
        case .firing(let snapshot, _)?:
            if zone == .recovered || zone == .unplugged {
                phases[signal] = nil
                return [.ended(signal)]
            }
            phases[signal] = .firing(snapshot: snapshot, recoveredSince: nil)
            effects += refresh(signal, rule: rule, observation: observation)
        case .pending(let start, let since)?:
            switch zone {
            case .firing, .between:
                phases[signal] = .pending(start: start, recoveredSince: nil)
            case .recovered:
                phases[signal] = .pending(start: start, recoveredSince: since ?? now)
            case .unplugged:
                phases[signal] = nil
            }
        case nil:
            if zone == .firing {
                phases[signal] = .pending(start: now, recoveredSince: nil)
            }
        }
        effects += step(signal, at: now)
        return effects
    }

    /// An `updated` effect when the visible value or the severity of a firing alert changed.
    private mutating func refresh(
        _ signal: AlertSignal,
        rule: ThresholdRule,
        observation: AlertObservation
    ) -> [Effect] {
        guard case .firing(let snapshot, let since)? = phases[signal] else {
            return []
        }
        let updated = AlertSnapshot(
            signal: signal,
            severity: AlertSeverity.of(observation, rule: rule),
            observation: observation
        )
        guard updated.severity != snapshot.severity
            || AlertLook.shortValue(of: updated.observation) != AlertLook.shortValue(of: snapshot.observation)
        else {
            return []
        }
        phases[signal] = .firing(snapshot: updated, recoveredSince: since)
        return [.updated(updated)]
    }
}
