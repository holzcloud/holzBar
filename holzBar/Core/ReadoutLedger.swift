//
//  ReadoutLedger.swift
//  holzBar
//

import Foundation

/// A measurement of the system readouts: one number or state the monitor reads for its consumers.
nonisolated enum ReadoutMetric: String, CaseIterable, Sendable {
    /// The load of all processors together.
    case cpu
    /// The load of every core, for the cluster split.
    case cpuCores
    /// The memory in use and the total.
    case memory
    /// The swap in use and the total.
    case swap
    /// The memory pressure level.
    case memoryPressure
    /// The bytes received and sent over the counted interfaces.
    case network
    /// The bytes read from and written to the disks.
    case diskActivity
    /// The free and the total space of the startup volume.
    case diskSpace
    /// The battery, its time and the adapter's watts.
    case power
    /// The thermal state of the Mac.
    case thermal
    /// The load of the graphics processor.
    case gpu
    /// The batteries of the accessories (a keyboard, a mouse, headphones), read through the one
    /// agreed accessory battery read and only while Read battery levels is on. Timed, not an
    /// event: a power source event only nudges it (see ``ReadoutSchedule/observers(ledger:isPaused:)``).
    case deviceBattery

    /// Whether the system announces a change by itself: it is observed while a consumer asks for
    /// it and never read on a timer (memory pressure, a power source event, the thermal state).
    var isEvent: Bool {
        switch self {
        case .memoryPressure, .power, .thermal:
            true
        case .cpu, .cpuCores, .memory, .swap, .network, .diskActivity, .diskSpace, .gpu, .deviceBattery:
            false
        }
    }
}

/// Why a consumer asks for readings.
nonisolated enum ReadoutConsumerKind: Equatable, Sendable {
    /// A surface the user sees: the hub tiles, a widget. Its consumer registers only while the
    /// surface is shown and the Mac is in use.
    case visible
    /// Something that watches without a surface (an alert of a later phase).
    case background
}

/// What one consumer wants measured, and how often.
nonisolated struct ReadoutRequest: Equatable, Sendable {
    /// The metrics the consumer reads.
    var metrics: Set<ReadoutMetric>
    /// The seconds between two readings of the timed metrics. The schedule keeps it inside 1 to
    /// ``ReadoutSchedule/maximumIntervalSeconds``.
    var intervalSeconds: Int
    /// Whether the consumer needs a baseline reading before its first value: a rate (CPU, network,
    /// disk) is the difference of two readings, so the second one follows after
    /// ``ReadoutSchedule/baselineDelay``.
    var needsBaseline: Bool
}

/// The consumers that ask the system readouts monitor for readings (D-01).
///
/// A pure value: it holds who asks for what, and says nothing about a clock or a sampler. While it
/// is idle, nothing is measured: ``ReadoutSchedule`` gives no tick and no observer (MON-08).
nonisolated struct ReadoutLedger: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        var kind: ReadoutConsumerKind
        var request: ReadoutRequest
    }

    private var entries: [String: Entry] = [:]

    /// Adds a consumer, or replaces the consumer with the same id.
    mutating func register(_ id: String, kind: ReadoutConsumerKind, request: ReadoutRequest) {
        entries[id] = Entry(kind: kind, request: request)
    }

    /// Removes a consumer; an id that is not registered changes nothing.
    mutating func unregister(_ id: String) {
        entries[id] = nil
    }

    /// Whether no consumer is registered, so nothing needs measuring.
    var isIdle: Bool {
        entries.isEmpty
    }

    /// Every metric some consumer asks for.
    var metrics: Set<ReadoutMetric> {
        entries.values.reduce(into: Set<ReadoutMetric>()) { $0.formUnion($1.request.metrics) }
    }

    /// The metrics that the system announces by itself and some consumer asks for.
    var eventMetrics: Set<ReadoutMetric> {
        metrics.filter(\.isEvent)
    }

    /// How many consumers show a surface.
    var visibleCount: Int {
        entries.values.filter { $0.kind == .visible }.count
    }

    /// How many consumers watch without a surface.
    var backgroundCount: Int {
        entries.values.filter { $0.kind == .background }.count
    }

    /// The ids of the registered consumers, sorted.
    var consumerIDs: [String] {
        entries.keys.sorted()
    }

    /// What a consumer asked for; `nil` for an id that is not registered.
    func request(for id: String) -> ReadoutRequest? {
        entries[id]?.request
    }
}

/// When the next readings are due: a pure function of the ledger, what was delivered to whom, the
/// instant, Low Power Mode and whether the Mac rests (D-01, D-12).
///
/// The monitor is the only caller. "Visible" is decided by the consumers (the widget policy,
/// ``ReadoutVisibility``), never by the monitor; the paused rule here is a second safety on top.
/// With no consumer, or while the Mac rests, there is no tick and no observer.
nonisolated enum ReadoutSchedule {
    /// A timed tick is never sooner than this from now, so a crafted interval cannot make a busy
    /// loop.
    static let minimumDelay = Duration.milliseconds(250)
    /// How long after its first reading a consumer that needs a baseline takes the second one.
    static let baselineDelay = Duration.seconds(1)
    /// The share of a delay the system may add to a timer, and the share that consumers may differ
    /// by and still share one tick.
    static let toleranceFraction = 0.1
    /// The longest interval a request is read at, in seconds (an hour).
    static let maximumIntervalSeconds = 3_600
    /// How long the free disk space is kept before it is read again.
    static let diskSpaceRefresh = Duration.seconds(60)

    /// When a consumer last received readings, and how many times.
    nonisolated struct Delivery: Equatable, Sendable {
        var last: ContinuousClock.Instant
        var count: Int
    }

    /// The next reading: when, how much the system may delay it, whom it serves and what it reads.
    nonisolated struct Tick: Equatable, Sendable {
        var at: ContinuousClock.Instant
        var tolerance: Duration
        /// The ids of the consumers it serves, sorted.
        var consumers: [String]
        /// The metrics to read: all the requested ones for a consumer that has had no reading yet,
        /// the timed ones for the others.
        var metrics: Set<ReadoutMetric>
    }

    private struct Candidate {
        var id: String
        var due: ContinuousClock.Instant
        var step: Duration
        var metrics: Set<ReadoutMetric>
    }

    /// The next tick, or `nil` when nothing is to be read: the ledger is idle, the Mac rests, or
    /// every consumer is served by events alone.
    ///
    /// - A consumer without a reading is due at `now` with all its metrics, events included (it
    ///   needs the first value).
    /// - Then a consumer that needs a baseline is due ``baselineDelay`` after its first reading,
    ///   not doubled in Low Power Mode; every other reading is due at the interval after the last,
    ///   doubled in Low Power Mode.
    /// - A consumer whose metrics are all events is due once.
    /// - A timed tick is never sooner than ``minimumDelay`` from now.
    /// - Consumers due within ``toleranceFraction`` of the earliest step share its tick.
    static func nextTick(
        ledger: ReadoutLedger,
        deliveries: [String: Delivery],
        now: ContinuousClock.Instant,
        isLowPowerMode: Bool,
        isPaused: Bool
    ) -> Tick? {
        guard !isPaused, !ledger.isIdle else {
            return nil
        }
        var candidates: [Candidate] = []
        for id in ledger.consumerIDs {
            guard let request = ledger.request(for: id) else {
                continue
            }
            let interval = effectiveInterval(request, isLowPowerMode: isLowPowerMode)
            guard let delivery = deliveries[id], delivery.count >= 1 else {
                candidates.append(Candidate(id: id, due: now, step: interval, metrics: request.metrics))
                continue
            }
            let timed = request.metrics.filter { !$0.isEvent }
            guard !timed.isEmpty else {
                continue
            }
            let step = delivery.count == 1 && request.needsBaseline ? baselineDelay : interval
            let due = max(delivery.last + step, now + minimumDelay)
            candidates.append(Candidate(id: id, due: due, step: step, metrics: timed))
        }
        let earliest = candidates.min { first, second in
            first.due == second.due ? first.id < second.id : first.due < second.due
        }
        guard let earliest else {
            return nil
        }
        let tolerance = tolerance(of: earliest.step)
        let sharing = candidates.filter { $0.due <= earliest.due + tolerance }
        return Tick(
            at: earliest.due,
            tolerance: tolerance,
            consumers: sharing.map(\.id).sorted(),
            metrics: sharing.reduce(into: Set<ReadoutMetric>()) { $0.formUnion($1.metrics) }
        )
    }

    /// The event metrics to observe: those some consumer asks for, and none while the Mac rests or
    /// no consumer is registered. A consumer of the device battery also asks for the power source
    /// event: an accessory's level change arrives as one, so it is delivered without waiting for
    /// the timed tick.
    static func observers(ledger: ReadoutLedger, isPaused: Bool) -> Set<ReadoutMetric> {
        guard !isPaused else {
            return []
        }
        var observed = ledger.eventMetrics
        if ledger.metrics.contains(.deviceBattery) {
            observed.insert(.power)
        }
        return observed
    }

    /// Whether the free disk space is read again: it was never read, or ``diskSpaceRefresh`` has
    /// passed.
    static func refreshesDiskSpace(lastRefresh: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let lastRefresh else {
            return true
        }
        return now - lastRefresh >= diskSpaceRefresh
    }

    // MARK: Arithmetic

    /// The interval of a request inside 1 to ``maximumIntervalSeconds``, doubled in Low Power
    /// Mode.
    private static func effectiveInterval(_ request: ReadoutRequest, isLowPowerMode: Bool) -> Duration {
        .seconds(effectiveSeconds(forInterval: request.intervalSeconds, isLowPowerMode: isLowPowerMode))
    }

    /// The seconds between two readings of a request with this interval: inside 1 to
    /// ``maximumIntervalSeconds``, doubled in Low Power Mode. The one place the rule lives, so a
    /// consumer that judges the spacing of the samples (the history curves) asks it instead of
    /// repeating it.
    static func effectiveSeconds(forInterval seconds: Int, isLowPowerMode: Bool) -> Int {
        min(max(seconds, 1), maximumIntervalSeconds) * (isLowPowerMode ? 2 : 1)
    }

    /// A tenth of a step, in whole milliseconds.
    private static func tolerance(of step: Duration) -> Duration {
        let components = step.components
        let milliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
        return .milliseconds(Int((milliseconds * toleranceFraction).rounded()))
    }
}

/// Whether a surface that reads the system readouts (the hub tiles) is a consumer right now: it
/// is shown, the Mac is in use and the menu bar has settled since (D-12).
///
/// The same rule as ``WidgetRefreshPolicy`` has for a widget, for a consumer that is not a widget.
/// The host feeds it the shown flag of its surface and the paused flag of `SystemActivityMonitor`
/// with the instant of each, and registers or unregisters the consumer as it says. After a pause it
/// waits ``SystemActivity/settleDelay`` before it registers again, and not at all when the surface
/// was closed meanwhile.
nonisolated struct ReadoutVisibility: Equatable, Sendable {
    /// Something that changes whether the surface is a consumer.
    nonisolated enum Event: Equatable, Sendable {
        /// The surface is shown or hidden.
        case shown(Bool)
        /// The Mac is not in use (`SystemActivity.isPaused`).
        case paused(Bool)
        /// The wait the host armed after a ``Change/waitUntil(_:)`` is over.
        case settleElapsed
    }

    /// What the host does after an event.
    nonisolated enum Change: Equatable, Sendable {
        /// Leave the consumer as it is.
        case keep
        /// Register the consumer.
        case register
        /// Unregister the consumer.
        case unregister
        /// Register nothing yet; send ``Event/settleElapsed`` at the instant.
        case waitUntil(ContinuousClock.Instant)
    }

    private var isShown = false
    private var isPaused = false
    private var settlesAt: ContinuousClock.Instant?
    private var isWaiting = false
    private var isRegistered = false

    /// Whether the consumer is registered: true exactly between a register and the next
    /// unregister.
    var isVisible: Bool {
        isRegistered
    }

    /// Takes in an event that happened at `now` and says what the host does.
    mutating func handle(_ event: Event, at now: ContinuousClock.Instant) -> Change {
        switch event {
        case .shown(let isShown):
            self.isShown = isShown
            return evaluate(at: now, repeatsWait: false)
        case .paused(let isPaused):
            if isPaused {
                self.isPaused = true
                settlesAt = nil
            } else if self.isPaused {
                self.isPaused = false
                settlesAt = now + SystemActivity.settleDelay
            }
            return evaluate(at: now, repeatsWait: false)
        case .settleElapsed:
            return evaluate(at: now, repeatsWait: true)
        }
    }

    private mutating func evaluate(at now: ContinuousClock.Instant, repeatsWait: Bool) -> Change {
        guard isShown, !isPaused else {
            isWaiting = false
            guard isRegistered else {
                return .keep
            }
            isRegistered = false
            return .unregister
        }
        guard !isRegistered else {
            return .keep
        }
        if let settlesAt {
            if now < settlesAt {
                guard repeatsWait || !isWaiting else {
                    return .keep
                }
                isWaiting = true
                return .waitUntil(settlesAt)
            }
            self.settlesAt = nil
        }
        isWaiting = false
        isRegistered = true
        return .register
    }
}
