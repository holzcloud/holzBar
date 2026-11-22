//
//  ThresholdRule.swift
//  holzBar
//

import Foundation

/// What a System alerts rule watches. There are five and no more (D-10): the rules cannot be added,
/// removed or reordered. The declaration order is the order of the alert rules (ALRT-01), of the
/// settings and of every list of effects the evaluator returns; the raw values are the stems of
/// activity and notification identifiers. New cases go at the end.
nonisolated enum AlertSignal: String, CaseIterable, Sendable {
    /// The load of all processors together.
    case cpu
    /// The memory pressure level.
    case memoryPressure
    /// The thermal state of the Mac, never degrees.
    case thermal
    /// The free space of the startup volume.
    case freeDisk
    /// The charge of the Mac's own battery, on battery power only.
    case macBattery
}

/// How long a condition has to hold before an alert fires (D-12): a fixed menu, not a free number.
nonisolated enum AlertHold: Int, CaseIterable, Sendable {
    case immediately = 0
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    /// The hold as a duration; a duration is never a sum of `Double`s.
    var duration: Duration {
        .seconds(rawValue)
    }

    /// The preset nearest to a number of seconds, a tie to the shorter one. Anything stored or
    /// imported lands on a preset (T-95-02): a negative number is "immediately", a huge one is the
    /// longest preset.
    static func snapped(seconds: Int) -> AlertHold {
        let clamped = min(max(seconds, 0), AlertHold.fifteenMinutes.rawValue)
        var best = AlertHold.immediately
        var bestDistance = Int.max
        for hold in allCases {
            let distance = abs(hold.rawValue - clamped)
            if distance < bestDistance {
                best = hold
                bestDistance = distance
            }
        }
        return best
    }
}

/// One alert rule: a signal, whether it is on, its threshold or level and how long it has to hold
/// (D-10 to D-13).
///
/// ``limit`` is read by the signal:
/// - CPU load: the percent, 50 to 95 in steps of 5.
/// - Memory pressure: the level, 1 for Warning or 2 for Critical (a level index, not the raw value
///   of ``ReadoutPressure``, so the settings schema's whole-number range 1 to 2 holds exactly the
///   values accepted here).
/// - Thermal state: the level, 1 for Fair, 2 for Serious or 3 for Critical (the raw values of
///   ``ReadoutThermal``).
/// - Free disk space: the gigabytes (decimal, 1 GB is 1 000 000 000 bytes), one of
///   ``diskLimitsGB``.
/// - Mac battery: the percent, 5 to 50 in steps of 5.
///
/// The settings can hold any number (a hand-edited file, an import), so every consumer brings a
/// stored limit through ``validatedLimit(_:for:)`` (T-95-02).
nonisolated struct ThresholdRule: Equatable, Sendable {
    var signal: AlertSignal
    var isOn: Bool
    var limit: Int
    var hold: AlertHold

    /// The range of a CPU threshold, in percent.
    static let cpuLimits: ClosedRange<Int> = 50...95
    /// The range of a Mac battery threshold, in percent.
    static let batteryLimits: ClosedRange<Int> = 5...50
    /// The levels of a memory pressure rule: 1 Warning, 2 Critical.
    static let memoryLevels: ClosedRange<Int> = 1...2
    /// The levels of a thermal state rule: 1 Fair, 2 Serious, 3 Critical.
    static let thermalLevels: ClosedRange<Int> = 1...3
    /// The step of a CPU and a battery threshold.
    static let limitStep = 5
    /// The thresholds a free disk space rule offers, in gigabytes.
    static let diskLimitsGB = [5, 10, 20, 50, 100, 200]
    /// Decimal gigabytes, the unit Finder shows.
    static let bytesPerGigabyte: Int64 = 1_000_000_000

    /// The rule of a signal nobody stored (D-11, D-12). Memory pressure is off because it is noisy
    /// on a small Mac; where the decisions are silent the contract gives memory pressure and free
    /// disk space a hold of one minute.
    static func defaultRule(for signal: AlertSignal) -> ThresholdRule {
        switch signal {
        case .cpu:
            ThresholdRule(signal: .cpu, isOn: true, limit: 90, hold: .fiveMinutes)
        case .memoryPressure:
            ThresholdRule(signal: .memoryPressure, isOn: false, limit: 1, hold: .oneMinute)
        case .thermal:
            ThresholdRule(signal: .thermal, isOn: true, limit: 2, hold: .immediately)
        case .freeDisk:
            ThresholdRule(signal: .freeDisk, isOn: true, limit: 10, hold: .oneMinute)
        case .macBattery:
            ThresholdRule(signal: .macBattery, isOn: true, limit: 20, hold: .immediately)
        }
    }

    /// A stored limit brought into what its signal accepts (T-95-02): CPU and battery clamp into
    /// their range and then snap to the nearest step; a disk size snaps to the nearest preset (a
    /// tie to the smaller); a level that does not exist falls back to the default level.
    static func validatedLimit(_ value: Int, for signal: AlertSignal) -> Int {
        switch signal {
        case .cpu:
            snappedStep(value, in: cpuLimits)
        case .macBattery:
            snappedStep(value, in: batteryLimits)
        case .freeDisk:
            nearestDiskLimit(value)
        case .memoryPressure:
            memoryLevels.contains(value) ? value : defaultRule(for: .memoryPressure).limit
        case .thermal:
            thermalLevels.contains(value) ? value : defaultRule(for: .thermal).limit
        }
    }

    /// This rule with its limit validated.
    var validated: ThresholdRule {
        var rule = self
        rule.limit = Self.validatedLimit(limit, for: signal)
        return rule
    }

    /// The threshold of a free disk space rule in bytes; zero for every other signal.
    var thresholdBytes: Int64 {
        signal == .freeDisk ? Int64(limit) * Self.bytesPerGigabyte : 0
    }

    /// The level of a memory pressure rule: 1 is Warning, anything else Critical's number 2.
    var pressureLevel: ReadoutPressure {
        limit == 2 ? .critical : .warning
    }

    /// The level of a thermal state rule; Serious for a number that is none.
    var thermalLevel: ReadoutThermal {
        ReadoutThermal(rawValue: limit) ?? .serious
    }

    private static func snappedStep(_ value: Int, in range: ClosedRange<Int>) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        // The bounds are multiples of the step, so the nearest multiple stays inside the range.
        return (clamped + limitStep / 2) / limitStep * limitStep
    }

    private static func nearestDiskLimit(_ value: Int) -> Int {
        // Clamped first so that no distance can overflow.
        let clamped = min(max(value, 0), 10_000)
        var best = diskLimitsGB[0]
        var bestDistance = Int.max
        for limit in diskLimitsGB {
            let distance = abs(limit - clamped)
            if distance < bestDistance {
                best = limit
                bestDistance = distance
            }
        }
        return best
    }
}
