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

    /// Takes the rules in force. A rule that is off (or missing) ends its alert.
    mutating func configure(_ newRules: [ThresholdRule], at now: SuspendingClock.Instant) -> [Effect] {
        var effects: [Effect] = []
        for signal in AlertSignal.allCases {
            let rule = newRules.first { $0.signal == signal }?.validated
            rules[signal] = rule?.isOn == true ? rule : nil
            guard rules[signal] == nil else {
                continue
            }
            if case .firing? = phases[signal] {
                effects.append(.ended(signal))
            }
            phases[signal] = nil
            latest[signal] = nil
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

    /// The earliest instant a pending alert may fire.
    private func earliestFire(_ signal: AlertSignal, start: SuspendingClock.Instant) -> SuspendingClock.Instant {
        start + (rules[signal]?.hold.duration ?? .zero)
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
            guard now >= earliestFire(signal, start: start) else {
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
