//
//  WidgetReadings.swift
//  holzBar
//

import Foundation

/// The processor tick counters of one reading of `host_processor_info`, summed over the cores.
///
/// A load is the difference of two readings (``WidgetReadings/cpuLoad(from:to:)``).
nonisolated struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

/// The page counts of one reading of `host_statistics64`.
nonisolated struct MemoryPages: Equatable, Sendable {
    /// The pages of anonymous (internal) memory.
    var internalPages: UInt64
    /// The pages the system may take back at once, counted inside ``internalPages``.
    var purgeable: UInt64
    var wired: UInt64
    var compressed: UInt64

    /// The bytes in use, the way Activity Monitor counts "Memory Used": internal pages less the
    /// purgeable ones (never below zero), plus wired and compressed pages. The sum saturates
    /// instead of trapping.
    func usedBytes(pageSize: UInt64) -> UInt64 {
        let application = internalPages > purgeable ? internalPages - purgeable : 0
        let pages = WidgetReadings.saturatingSum(application, wired, compressed)
        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        return overflow ? UInt64.max : bytes
    }
}

/// What a battery's power source flags say, for the symbol next to the percentage.
nonisolated enum BatteryState: Equatable, Sendable {
    case charging
    case charged
    case onBattery
    case onAdapter

    /// The state of the power source flags. A source that reports battery power is discharging,
    /// whatever its other flags say; then a full battery on the adapter, then one that charges;
    /// a battery on the adapter that does not charge (it holds its level) is on the adapter.
    init(isOnBattery: Bool, isCharging: Bool, isCharged: Bool) {
        if isOnBattery {
            self = .onBattery
        } else if isCharged {
            self = .charged
        } else if isCharging {
            self = .charging
        } else {
            self = .onAdapter
        }
    }
}

/// The value one source gave at one moment, with no text made from it yet.
///
/// A source that could not be read is ``unavailable``: the text shows an en dash and never an
/// earlier value as if it were current (D-13).
nonisolated enum WidgetReading: Equatable, Sendable {
    case date(Date)
    case battery(percent: Int, state: BatteryState)
    /// A part of a whole, from 0 to 1: CPU load, memory used, free disk space.
    case fraction(Double)
    case bytes(UInt64)
    case duration(Duration)
    case countdown(remaining: Duration, isPassed: Bool)
    /// The first line of an approved script's output, already cleaned and cut to
    /// ``ScriptOutput/maximumDisplayLength`` characters by ``ScriptOutput/displayLine(_:)``. It
    /// is plain text: never parsed, opened or interpreted (D-23, T-12-25).
    case line(String)
    case unavailable
}

/// The arithmetic behind the widgets' readings: value in, value out, with no timer, no UI and
/// no call into the system (D-03). The app's samplers read the numbers and hand them in; the
/// system readouts of a later phase use the same functions.
nonisolated enum WidgetReadings {
    /// The share of ticks the processors were busy between two readings, from 0 to 1: user,
    /// system and nice ticks over all ticks.
    ///
    /// - Returns: `nil` when no ticks passed, or when a counter went backwards (it wrapped, or the
    ///   readings are not from one boot).
    static func cpuLoad(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        guard current.user >= previous.user, current.system >= previous.system,
            current.idle >= previous.idle, current.nice >= previous.nice else {
            return nil
        }
        let busy = Double(current.user - previous.user) + Double(current.system - previous.system)
            + Double(current.nice - previous.nice)
        let total = busy + Double(current.idle - previous.idle)
        guard total > 0 else {
            return nil
        }
        return busy / total
    }

    /// The share of the memory in use, from 0 to 1; `nil` for a total of zero.
    static func usedFraction(used: UInt64, total: UInt64) -> Double? {
        guard total > 0 else {
            return nil
        }
        return min(Double(used) / Double(total), 1)
    }

    /// The share of a volume that is free, from 0 to 1; `nil` when the total is not above zero or
    /// the available capacity is negative (the volume did not answer).
    static func diskFreeFraction(available: Int64, total: Int64) -> Double? {
        guard total > 0, available >= 0 else {
            return nil
        }
        return min(Double(available) / Double(total), 1)
    }

    /// The time since boot; `nil` when the boot is after `now` (the clock was set back).
    static func uptime(now: Date, boot: Date) -> Duration? {
        let seconds = now.timeIntervalSince(boot)
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return .seconds(seconds)
    }

    /// The seconds of a duration, with its fraction.
    static func seconds(of duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// The sum of three counts, or ``UInt64/max`` when it would overflow.
    fileprivate static func saturatingSum(_ first: UInt64, _ second: UInt64, _ third: UInt64) -> UInt64 {
        let (partial, firstOverflow) = first.addingReportingOverflow(second)
        let (sum, secondOverflow) = partial.addingReportingOverflow(third)
        return firstOverflow || secondOverflow ? UInt64.max : sum
    }
}

/// The time left to a fixed moment (D-02): it only displays, and never sends a notification.
nonisolated enum Countdown {
    /// The time left; zero once the moment has passed, never negative.
    static func remaining(now: Date, target: Date) -> Duration {
        let seconds = target.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else {
            return .zero
        }
        return .seconds(seconds)
    }

    /// The seconds until the minutes shown change: the remaining time modulo one minute, and 60
    /// when it is a whole number of minutes (the text counts minutes rounded up, so it holds
    /// until the next minute boundary). `nil` once the moment has passed: nothing changes then.
    static func secondsToNextChange(remaining: Duration) -> Double? {
        let seconds = WidgetReadings.seconds(of: remaining)
        guard seconds > 0 else {
            return nil
        }
        let rest = seconds.truncatingRemainder(dividingBy: 60)
        return rest == 0 ? 60 : rest
    }

    /// The reading of a countdown at `now`.
    static func reading(now: Date, target: Date) -> WidgetReading {
        .countdown(remaining: remaining(now: now, target: target), isPassed: target <= now)
    }
}
