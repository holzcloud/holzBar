//
//  SystemMonitor.swift
//  holzBar
//

import Foundation
import Observation

/// The one shared monitor of the system readouts (D-01): the widgets, the hub tiles and later the
/// alerts register what they want measured, and this reads it once for all of them.
///
/// It holds a ``ReadoutLedger`` of consumers and one timer task. After every change of the ledger,
/// of the Mac's rest or of Low Power Mode it asks ``ReadoutSchedule/nextTick(ledger:deliveries:now:isLowPowerMode:isPaused:)``
/// when to wake, sleeps until then, reads off the main actor with ``SystemSamplers/read(_:refreshesDiskSpace:)``
/// and delivers the plain values to the consumers on the main actor. A rate is the business of
/// the consumer: it keeps its own baseline, so two consumers with different intervals each measure
/// from their own previous sample.
///
/// The memory pressure, the power source and the thermal state are events, never polled (D-10):
/// while a consumer asks for one the monitor holds the system's own event source for it (a dispatch
/// source, the shared power source run loop source, a notification task), and ends it when no one
/// asks.
///
/// With no consumer, or while the Mac rests, there is no task and no observer (MON-08): the
/// ledger is idle and nothing runs. Everything here lives on the main actor, so no lock is
/// needed (D-10): the sampler gets plain `Sendable` arguments and returns a `Sendable` sample.
/// It never logs a reading (D-14), and it never touches the network.
@MainActor
@Observable
final class SystemMonitor {
    /// How many consumers show a surface right now.
    private(set) var visibleCount = 0
    /// How many consumers watch without a surface.
    private(set) var backgroundCount = 0
    /// How many event metrics the schedule asks to observe.
    private(set) var observerCount = 0
    /// Whether the one timer task is armed.
    private(set) var isTimerArmed = false
    /// How many samples were taken since holzBar started.
    private(set) var samplesTaken = 0

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var ledger = ReadoutLedger()
    @ObservationIgnored private var deliveries = [String: ReadoutSchedule.Delivery]()
    @ObservationIgnored private var sinks = [String: @MainActor (ReadoutSample) -> Void]()
    /// The one task that sleeps until the next tick, reads and delivers.
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    /// Tells a task that was replaced from the current one.
    @ObservationIgnored private var generation = 0
    /// Follows whether the Mac rests, only while the ledger is not idle.
    @ObservationIgnored private var pauseLoop: ObservationLoop?
    /// Follows Low Power Mode, only while the ledger is not idle.
    @ObservationIgnored private var powerTask: Task<Void, Never>?
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var isLowPowerMode = false
    /// The system's memory pressure events, while a consumer asks for the pressure.
    @ObservationIgnored private var pressureWatch: MemoryPressureWatch?
    /// The task that follows power source events, while a consumer asks for the power; it holds one
    /// use of the shared run loop source, which it gives back when it ends.
    @ObservationIgnored private var powerEventTask: Task<Void, Never>?
    /// The task that follows the thermal state notification, while a consumer asks for it.
    @ObservationIgnored private var thermalTask: Task<Void, Never>?
    /// The free disk space as the last precise read left it, and when that was (D-10).
    @ObservationIgnored private var preciseDiskSpace: DiskSpace?
    @ObservationIgnored private var preciseDiskSpaceAt: ContinuousClock.Instant?

    /// Keeps the app state, which says whether the Mac rests. Starts nothing: the monitor wakes
    /// only when a consumer registers.
    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    /// Adds a consumer, or replaces the consumer with the same id: its deliveries start again, so
    /// its first reading comes at once.
    ///
    /// - Parameters:
    ///   - id: The consumer's identifier, such as `widget.<uuid>`.
    ///   - kind: Whether the consumer shows a surface or watches.
    ///   - request: What it wants measured and how often.
    ///   - deliver: Called on the main actor with every sample the consumer is served by.
    func register(
        _ id: String,
        kind: ReadoutConsumerKind,
        request: ReadoutRequest,
        deliver: @escaping @MainActor (ReadoutSample) -> Void
    ) {
        ledger.register(id, kind: kind, request: request)
        deliveries[id] = nil
        sinks[id] = deliver
        reschedule()
    }

    /// Removes a consumer. An id that is not registered changes nothing.
    func unregister(_ id: String) {
        guard sinks[id] != nil else {
            return
        }
        ledger.unregister(id)
        deliveries[id] = nil
        sinks[id] = nil
        reschedule()
    }

    // MARK: Scheduling

    /// Replaces the timer task with one for the next tick, or with none when nothing is to be
    /// read. Called after every change of what the schedule depends on.
    private func reschedule() {
        generation &+= 1
        timerTask?.cancel()
        timerTask = nil
        updateObservations()
        let now = ContinuousClock.now
        let tick = ReadoutSchedule.nextTick(
            ledger: ledger,
            deliveries: deliveries,
            now: now,
            isLowPowerMode: isLowPowerMode,
            isPaused: isPaused
        )
        visibleCount = ledger.visibleCount
        backgroundCount = ledger.backgroundCount
        let observers = ReadoutSchedule.observers(ledger: ledger, isPaused: isPaused)
        observerCount = observers.count
        updateEventObservers(observers)
        isTimerArmed = tick != nil
        guard let tick else {
            return
        }
        let token = generation
        timerTask = Task { [weak self] in
            do {
                try await Task.sleep(until: tick.at, tolerance: tick.tolerance, clock: ContinuousClock())
            } catch {
                return
            }
            // The precise capacity of the volume is read about once a minute (D-10); the decision
            // is made here, on the main actor, where the cache lives.
            let refreshesDisk = self?.refreshesDiskSpace(for: tick) ?? false
            let sample = await SystemSamplers.read(tick.metrics, refreshesDiskSpace: refreshesDisk)
            self?.deliver(sample, for: tick, token: token, refreshedDiskSpace: refreshesDisk)
        }
    }

    /// Hands a sample to the consumers of its tick and schedules the next one. A tick that was
    /// replaced or cancelled while it read delivers nothing (T-94-05).
    private func deliver(
        _ read: ReadoutSample,
        for tick: ReadoutSchedule.Tick,
        token: Int,
        refreshedDiskSpace: Bool
    ) {
        guard token == generation else {
            return
        }
        let sample = cachingDiskSpace(of: read, refreshed: refreshedDiskSpace)
        samplesTaken += 1
        for id in tick.consumers where sinks[id] != nil {
            deliveries[id] = ReadoutSchedule.Delivery(last: sample.at, count: (deliveries[id]?.count ?? 0) + 1)
        }
        for id in tick.consumers {
            sinks[id]?(sample)
        }
        reschedule()
    }

    // MARK: Disk space

    /// Whether the tick reads the precise free space: it carries the disk space and the last
    /// precise read is a minute old or missing.
    private func refreshesDiskSpace(for tick: ReadoutSchedule.Tick) -> Bool {
        tick.metrics.contains(.diskSpace)
            && ReadoutSchedule.refreshesDiskSpace(lastRefresh: preciseDiskSpaceAt, now: .now)
    }

    /// Keeps a precise read, or puts the kept precise figure into a sample that has only the
    /// cheap one, so a consumer always gets the figure Finder shows and the capacity is asked of
    /// the system once a minute (D-10).
    private func cachingDiskSpace(of sample: ReadoutSample, refreshed: Bool) -> ReadoutSample {
        guard sample.read.contains(.diskSpace) else {
            return sample
        }
        if refreshed {
            preciseDiskSpace = sample.diskSpace
            preciseDiskSpaceAt = sample.diskSpace == nil ? nil : sample.at
            return sample
        }
        guard var space = sample.diskSpace, let kept = preciseDiskSpace else {
            return sample
        }
        space.available = kept.available
        space.total = kept.total
        var cached = sample
        cached.diskSpace = space
        return cached
    }

    // MARK: Event observers

    /// Starts or stops the event sources to match the schedule's observer plan: one source for each
    /// event metric a consumer asks for, none otherwise (MON-08).
    private func updateEventObservers(_ wanted: Set<ReadoutMetric>) {
        if wanted.contains(.memoryPressure) {
            if pressureWatch == nil {
                pressureWatch = MemoryPressureWatch { [weak self] level in
                    self?.pressureChanged(level)
                }
            }
        } else if let watch = pressureWatch {
            watch.cancel()
            pressureWatch = nil
        }
        updatePowerEvents(isWanted: wanted.contains(.power))
        updateThermalEvents(isWanted: wanted.contains(.thermal))
    }

    /// Takes one use of the shared power source run loop source while the power is asked for and
    /// gives it back when it is not: every `begin()` pairs with one `end()`, because the automation
    /// rules share the source (T-94-15).
    private func updatePowerEvents(isWanted: Bool) {
        if isWanted {
            guard powerEventTask == nil else {
                return
            }
            PowerSourceEvents.shared.begin()
            powerEventTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .powerSourcesDidChange) {
                    guard let self else {
                        return
                    }
                    powerChanged()
                }
            }
        } else if let task = powerEventTask {
            task.cancel()
            powerEventTask = nil
            PowerSourceEvents.shared.end()
        }
    }

    private func updateThermalEvents(isWanted: Bool) {
        if isWanted {
            guard thermalTask == nil else {
                return
            }
            // The notification may arrive on any thread; the loop runs on the main actor, so the
            // state is read and delivered there (T-94-16). Never a timer (D-10).
            thermalTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: ProcessInfo.thermalStateDidChangeNotification
                ) {
                    guard let self else {
                        return
                    }
                    thermalChanged()
                }
            }
        } else if let task = thermalTask {
            task.cancel()
            thermalTask = nil
        }
    }

    /// Delivers the new level to every consumer that asks for it, as a sample that holds the
    /// pressure and nothing else.
    private func pressureChanged(_ level: ReadoutPressure) {
        var sample = ReadoutSample(at: ContinuousClock.now)
        sample.read = [.memoryPressure]
        sample.memoryPressure = level
        deliverEvent(sample, of: .memoryPressure)
    }

    private func powerChanged() {
        var sample = ReadoutSample(at: ContinuousClock.now)
        sample.read = [.power]
        sample.power = SystemSamplers.powerReading()
        deliverEvent(sample, of: .power)
    }

    private func thermalChanged() {
        var sample = ReadoutSample(at: ContinuousClock.now)
        sample.read = [.thermal]
        sample.thermal = SystemSamplers.thermalState()
        deliverEvent(sample, of: .thermal)
    }

    /// Hands an event sample to every consumer whose request holds the metric.
    private func deliverEvent(_ sample: ReadoutSample, of metric: ReadoutMetric) {
        for id in ledger.consumerIDs where ledger.request(for: id)?.metrics.contains(metric) == true {
            sinks[id]?(sample)
        }
    }

    // MARK: Observations

    /// Follows the Mac's rest and Low Power Mode while a consumer is registered, and neither
    /// while the ledger is idle (MON-08).
    private func updateObservations() {
        guard !ledger.isIdle else {
            stopObservations()
            return
        }
        guard pauseLoop == nil else {
            return
        }
        isPaused = appState?.systemActivityMonitor.isPaused ?? false
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        weak let activity = appState?.systemActivityMonitor
        pauseLoop = ObservationLoop.observe {
            activity?.isPaused ?? false
        } onChange: { [weak self] isPaused in
            guard let self, self.isPaused != isPaused else {
                return
            }
            self.isPaused = isPaused
            reschedule()
        }
        powerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                guard let self else {
                    return
                }
                powerStateChanged()
            }
        }
    }

    private func stopObservations() {
        pauseLoop?.cancel()
        pauseLoop = nil
        powerTask?.cancel()
        powerTask = nil
        isPaused = false
    }

    private func powerStateChanged() {
        let isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard isOn != isLowPowerMode else {
            return
        }
        isLowPowerMode = isOn
        reschedule()
    }
}

/// The system's memory pressure events as one dispatch source on the main queue (D-10, D-12).
/// It exists only while a consumer asks for the pressure; cancelling it ends the events.
private nonisolated final class MemoryPressureWatch {
    private let source: any DispatchSourceMemoryPressure

    init(onChange: @escaping @MainActor @Sendable (ReadoutPressure) -> Void) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            guard let mask = source?.data.rawValue, let level = ReadoutPressure(eventMask: mask) else {
                return
            }
            // The source reports on the main queue.
            MainActor.assumeIsolated {
                onChange(level)
            }
        }
        self.source = source
        source.resume()
    }

    func cancel() {
        source.cancel()
    }

    deinit {
        source.cancel()
    }
}
