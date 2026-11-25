//
//  ReadoutHistory.swift
//  holzBar
//

import Foundation

/// A point of a mini curve, both coordinates from 0 to 1: `x` is the time (0 is the oldest end of
/// the window, 1 the newest, on the right edge) and `y` the height (0 at the baseline, 1 at the
/// top of the scale).
nonisolated struct CurvePoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// How a history's values map to the height of its curve (R1).
nonisolated enum ReadoutHistoryScale: Equatable, Sendable {
    /// A share from 0 to 1 on a fixed scale of 0 to 1.
    case fraction
    /// A rate on a scale from 0 to the window's peak, never below `floor`.
    case rate(floor: Double)
}

/// Where a history has been going over its window.
nonisolated enum ReadoutTrend: Equatable, Sendable {
    case rising
    case falling
    case steady
}

/// What VoiceOver says about a curve instead of the curve: the lowest and the highest value of
/// the window and where it went.
nonisolated struct ReadoutHistorySummary: Equatable, Sendable {
    var lowest: Double
    var highest: Double
    var trend: ReadoutTrend
}

/// The last two minutes of one readout, kept in memory for the mini curve of a hub tile (MON-10,
/// D-06): a small ring of timed values that only the deliveries of the open hub fill.
///
/// The policy is by time, not by count, so a slower refresh still covers about two minutes: a
/// sample older than ``window`` before the newest one drops off, and ``capacity`` bounds the
/// memory in any case. A missing value (`nil`) is kept as a gap, and a gap longer than 2.5 times
/// the interval the samples come at (the hub was closed in between) breaks the curve, so a closed hub is never
/// drawn as a flat value. Nothing here is stored, logged or exported.
nonisolated struct ReadoutHistory: Equatable, Sendable {
    /// How far back the history reaches.
    static let window = Duration.seconds(120)
    /// The most samples kept; a refresh of one second needs 120.
    static let capacity = 128
    /// The shortest time a history must cover before it has a summary.
    static let summaryMinimumSpan = Duration.seconds(20)
    /// The length of the two ends of the window that the trend compares.
    static let trendSpan = Duration.seconds(15)
    /// The change, as a share of the scale, above which a curve rises or falls.
    static let trendThreshold = 0.10

    private struct Sample: Equatable, Sendable {
        var instant: ContinuousClock.Instant
        var value: Double?
    }

    private var samples: [Sample] = []

    /// How many samples are kept.
    var count: Int { samples.count }

    init() {}

    /// Adds a value, `nil` when the reading is missing, stuck or impossible. A sample older than
    /// the newest one is put in its place in time.
    mutating func append(_ value: Double?, at instant: ContinuousClock.Instant) {
        let clean = value.flatMap { $0.isFinite ? $0 : nil }
        var index = samples.count
        while index > 0, samples[index - 1].instant > instant {
            index -= 1
        }
        samples.insert(Sample(instant: instant, value: clean), at: index)
        if let newest = samples.last?.instant {
            let oldest = newest - Self.window
            samples.removeAll { $0.instant < oldest }
        }
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    /// Forgets every sample.
    mutating func removeAll() {
        samples.removeAll()
    }

    /// The curve's lines: runs of two or more consecutive values, each point placed by its time
    /// and its height. A missing value and a gap of more than 2.5 times the interval end a run; a
    /// run of a single point is no line. The extra half interval leaves room for the timer's
    /// tolerance and the time a reading takes, so a steady sampling never breaks the curve.
    ///
    /// - Parameters:
    ///   - now: The right edge of the window.
    ///   - refreshSeconds: The interval the samples really come at, in seconds: the refresh
    ///     interval as the monitor applies it (``ReadoutSchedule/effectiveSeconds(forInterval:isLowPowerMode:)``).
    ///   - top: The value at the top of the scale: 1 for fractions, the peak for rates.
    func segments(now: ContinuousClock.Instant, refreshSeconds: Int, top: Double) -> [[CurvePoint]] {
        let maximumGap = Duration.milliseconds(max(refreshSeconds, 1) * 2_500)
        let height = top > 0 ? top : 1
        var runs: [[CurvePoint]] = []
        var current: [CurvePoint] = []
        var previous: ContinuousClock.Instant?
        func finish() {
            if current.count >= 2 {
                runs.append(current)
            }
            current = []
        }
        for sample in inWindow(now: now) {
            guard let value = sample.value else {
                finish()
                previous = nil
                continue
            }
            if let previous, sample.instant - previous > maximumGap {
                finish()
            }
            let x = 1 - Self.seconds(now - sample.instant) / Self.seconds(Self.window)
            current.append(CurvePoint(x: min(max(x, 0), 1), y: min(max(value / height, 0), 1)))
            previous = sample.instant
        }
        finish()
        return runs
    }

    /// The value at the top of the scale for histories drawn together: 1 for fractions, and for
    /// rates the peak of every history's window, never below the scale's floor.
    static func top(of histories: [ReadoutHistory], scale: ReadoutHistoryScale, now: ContinuousClock.Instant) -> Double {
        switch scale {
        case .fraction:
            return 1
        case .rate(let floor):
            let peak = histories
                .flatMap { $0.inWindow(now: now) }
                .compactMap(\.value)
                .max() ?? 0
            return max(peak, floor)
        }
    }

    /// The lowest and highest value of the window and its trend, or `nil` with less than 20
    /// seconds between the oldest and the newest value. The trend compares the mean of the
    /// newest 15 seconds with the mean of the oldest 15: a difference of more than a tenth of
    /// the scale is rising or falling.
    ///
    /// - Parameters:
    ///   - now: The right edge of the window.
    ///   - top: The value at the top of the scale (see ``top(of:scale:now:)``).
    func summary(now: ContinuousClock.Instant, top: Double) -> ReadoutHistorySummary? {
        let values = inWindow(now: now).compactMap { sample in
            sample.value.map { (instant: sample.instant, value: $0) }
        }
        guard let oldest = values.first, let newest = values.last,
              newest.instant - oldest.instant >= Self.summaryMinimumSpan else {
            return nil
        }
        let early = values.filter { $0.instant - oldest.instant <= Self.trendSpan }.map(\.value)
        let late = values.filter { newest.instant - $0.instant <= Self.trendSpan }.map(\.value)
        let change = Self.mean(late) - Self.mean(early)
        let limit = Self.trendThreshold * (top > 0 ? top : 1)
        let trend: ReadoutTrend = change > limit ? .rising : (change < -limit ? .falling : .steady)
        let all = values.map(\.value)
        return ReadoutHistorySummary(lowest: all.min() ?? 0, highest: all.max() ?? 0, trend: trend)
    }

    private func inWindow(now: ContinuousClock.Instant) -> [Sample] {
        let oldest = now - Self.window
        return samples.filter { $0.instant >= oldest && $0.instant <= now }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
