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
///
/// The GPU load is the one reading that goes through a private macOS interface (D-07): it is read
/// through ``GPULoadBridge`` only while the Read GPU load switch is on and the start check holds.
///
/// The accessory batteries (``ReadoutMetric/deviceBattery``) go through the one agreed accessory
/// battery read (the exception of 2026-10-16 in `CLAUDE.md`, widened on 2026-11-22), only while
/// Read battery levels is on and the call exists. This file never names the undocumented function
/// itself; it calls ``AccessoryBatterySource``, whose file is the only one that does.
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
    /// Whether the Read GPU load switch is on and the GPU part switched itself off for this
    /// session: the interface is missing, or three reads in a row failed. The tiles and the
    /// settings follow it (D-07).
    private(set) var gpuIsUnavailable = false

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var ledger = ReadoutLedger()
    @ObservationIgnored private var deliveries = [String: ReadoutSchedule.Delivery]()
    @ObservationIgnored private var sinks = [String: @MainActor (ReadoutSample) -> Void]()
    /// The one task that sleeps until the next tick, reads and delivers.
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    /// Tells a task that was replaced from the current one.
    @ObservationIgnored private var generation = 0
    /// The generation whose task is reading right now, or `nil` while none is.
    @ObservationIgnored private var readingToken: Int?
    /// How often each consumer registered, so a read can tell a consumer that registered anew
    /// (with a request it was not made for) from the one it was made for.
    @ObservationIgnored private var registrationEpochs = [String: Int]()
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
    /// The start check and the failure count of the GPU read, created at its first use after the
    /// Read GPU load switch went on and dropped when the switch changes (D-07).
    @ObservationIgnored private var gpuGate: PrivateFeatureGate?
    /// Whether a GPU read is in flight, so two never overlap (M-03).
    @ObservationIgnored private var isReadingGPU = false
    /// The one accessory battery read that is in flight, so two never overlap: a caller that comes
    /// while it runs waits for its result instead of starting another.
    @ObservationIgnored private var deviceRead: Task<[AccessoryBattery], Never>?
    /// The task that delivers the accessory batteries after power source events, while one is
    /// pending or reading, and whether another event came meanwhile.
    @ObservationIgnored private var deviceEventTask: Task<Void, Never>?
    @ObservationIgnored private var deviceEventPending = false

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
        registrationEpochs[id, default: 0] += 1
        reschedule(interruptingRead: false)
    }

    /// Removes a consumer. An id that is not registered changes nothing.
    func unregister(_ id: String) {
        guard sinks[id] != nil else {
            return
        }
        ledger.unregister(id)
        deliveries[id] = nil
        sinks[id] = nil
        registrationEpochs[id] = nil
        reschedule(interruptingRead: false)
    }

    // MARK: Scheduling

    /// Replaces the timer task with one for the next tick, or with none when nothing is to be
    /// read. Called after every change of what the schedule depends on.
    ///
    /// - Parameter interruptingRead: Whether a read that is already in flight is thrown away. A
    ///   change of the consumers does not interrupt it: the read finishes, goes to the consumers
    ///   of its tick that are still the same, and then the next tick is scheduled (L-04). The Mac's
    ///   rest and Low Power Mode interrupt it.
    private func reschedule(interruptingRead: Bool = true) {
        let isReadInFlight = readingToken == generation
        if !interruptingRead, isReadInFlight {
            updateObservations()
            visibleCount = ledger.visibleCount
            backgroundCount = ledger.backgroundCount
            let observers = ReadoutSchedule.observers(ledger: scheduledLedger(), isPaused: isPaused)
            observerCount = observers.count
            updateEventObservers(observers)
            return
        }
        generation &+= 1
        timerTask?.cancel()
        timerTask = nil
        updateObservations()
        let now = ContinuousClock.now
        let scheduled = scheduledLedger()
        let tick = ReadoutSchedule.nextTick(
            ledger: scheduled,
            deliveries: deliveries,
            now: now,
            isLowPowerMode: isLowPowerMode,
            isPaused: isPaused
        )
        visibleCount = ledger.visibleCount
        backgroundCount = ledger.backgroundCount
        let observers = ReadoutSchedule.observers(ledger: scheduled, isPaused: isPaused)
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
            guard let self, token == self.generation else {
                return
            }
            await read(tick, token: token)
        }
    }

    /// Reads what the tick asks for and delivers it. The read is in flight from here until it is
    /// delivered or dropped (``reschedule(interruptingRead:)``).
    private func read(_ tick: ReadoutSchedule.Tick, token: Int) async {
        readingToken = token
        defer {
            if readingToken == token {
                readingToken = nil
            }
        }
        // The consumers as they are now: one that registers again meanwhile (a new request) is
        // not served by this read (L-04).
        let epochs = registrationEpochs
        // The precise capacity of the volume is read about once a minute (D-10); the decision
        // is made here, on the main actor, where the cache lives.
        let refreshesDisk = refreshesDiskSpace(for: tick)
        var sample = await SystemSamplers.read(tick.metrics, refreshesDiskSpace: refreshesDisk)
        // A read that was interrupted must not go on to the private interface (M-03), and neither
        // must one whose consumers of the GPU load are all gone by now.
        guard !Task.isCancelled, token == generation else {
            return
        }
        if tick.metrics.contains(.gpu) {
            // The GPU goes through its own start check, on the main actor where the gate lives.
            sample.read.insert(.gpu)
            if stillWants(.gpu, in: tick, epochs: epochs) {
                sample.gpuPercent = await readGPU(token: token)
            }
        }
        if tick.metrics.contains(.deviceBattery) {
            // The accessory batteries go through the agreed read, behind its switch, on the main
            // actor where the one read in flight is kept.
            sample.read.insert(.deviceBattery)
            if stillWants(.deviceBattery, in: tick, epochs: epochs) {
                sample.deviceBatteries = await readDeviceBatteries(token: token)
            }
        }
        deliver(sample, for: tick, token: token, epochs: epochs, refreshedDiskSpace: refreshesDisk)
    }

    /// Whether a consumer of the tick that has not registered anew still asks for the metric.
    private func stillWants(_ metric: ReadoutMetric, in tick: ReadoutSchedule.Tick, epochs: [String: Int]) -> Bool {
        tick.consumers.contains { id in
            sinks[id] != nil && registrationEpochs[id] == epochs[id]
                && ledger.request(for: id)?.metrics.contains(metric) == true
        }
    }

    /// The ledger the schedule sees: a consumer of nothing but a gated read rests after its one
    /// reading while that read's switch is off (L-03), see
    /// ``ReadoutSchedule/scheduledLedger(_:deliveries:readsGPU:readsDeviceBattery:)``.
    private func scheduledLedger() -> ReadoutLedger {
        ReadoutSchedule.scheduledLedger(
            ledger,
            deliveries: deliveries,
            readsGPU: appState?.settings.readouts.readsGPU == true,
            readsDeviceBattery: AccessoryAlertsSettings.readsBattery()
        )
    }

    /// Hands a sample to the consumers of its tick and schedules the next one. A tick that was
    /// replaced or cancelled while it read delivers nothing (T-94-05).
    private func deliver(
        _ read: ReadoutSample,
        for tick: ReadoutSchedule.Tick,
        token: Int,
        epochs: [String: Int],
        refreshedDiskSpace: Bool
    ) {
        guard token == generation else {
            return
        }
        let sample = cachingDiskSpace(of: read, refreshed: refreshedDiskSpace)
        samplesTaken += 1
        let served = tick.consumers.filter { sinks[$0] != nil && registrationEpochs[$0] == epochs[$0] }
        for id in served {
            deliveries[id] = ReadoutSchedule.Delivery(last: sample.at, count: (deliveries[id]?.count ?? 0) + 1)
        }
        for id in served {
            sinks[id]?(sample)
        }
        reschedule()
    }

    // MARK: GPU

    /// The Read GPU load switch changed. The gate starts afresh at the next read: a part that
    /// failed stays off for the session until the user switches it off and on again, and nothing
    /// is probed while no one asks for the load (MON-08).
    ///
    /// Every consumer of the GPU load takes one fresh delivery now: no value while the switch is
    /// off (a GPU Load widget shows the en dash, never the last percent) and, when it is on, a real
    /// value whose first read is the start check. ``readGPU(token:)`` calls nothing of the bridge
    /// while the switch is off. The rest rule keeps a consumer of nothing but the GPU scheduled
    /// until that delivery, and a reading in flight is thrown away by the reschedule.
    func gpuSwitchDidChange() {
        gpuGate = nil
        gpuIsUnavailable = false
        deliveries = ReadoutSchedule.restartingDeliveries(deliveries, of: .gpu, in: ledger)
        reschedule()
    }

    /// Reads the GPU load through ``GPULoadBridge``, only while the switch is on and the gate is
    /// available; otherwise the bridge is not called at all. The first read after the switch went
    /// on is the start check, and three failed reads in a row switch the part off for the session.
    ///
    /// One read is in flight at most, and a read whose tick was replaced meanwhile (`token` is no
    /// longer the current generation) neither calls the bridge nor counts on the gate (M-03).
    private func readGPU(token: Int) async -> Int? {
        guard !isReadingGPU else {
            return nil
        }
        isReadingGPU = true
        defer { isReadingGPU = false }
        guard PrivateFeatureGate.shouldLoad(isEnabled: appState?.settings.readouts.readsGPU ?? false) else {
            gpuGate = nil
            updateGPUAvailability()
            return nil
        }
        if gpuGate == nil {
            let load = await GPULoadBridge.probe()
            if gpuGate == nil {
                gpuGate = PrivateFeatureGate(isEnabled: true, load: load)
            }
        }
        guard gpuGate?.isAvailable == true else {
            updateGPUAvailability()
            return nil
        }
        guard token == generation else {
            return nil
        }
        let reading = await GPULoadBridge.read()
        defer { updateGPUAvailability() }
        guard case .percent(let value) = reading else {
            gpuGate?.recordFailure()
            return nil
        }
        gpuGate?.recordSuccess()
        return value
    }

    private func updateGPUAvailability() {
        var switchedItselfOff = false
        if let gate = gpuGate, case .unavailable(let reason) = gate.state, reason != .switchedOff {
            switchedItselfOff = true
        }
        if gpuIsUnavailable != switchedItselfOff {
            gpuIsUnavailable = switchedItselfOff
        }
    }

    // MARK: Device batteries

    /// The Read battery levels switch changed. Every consumer of the device battery takes one fresh
    /// delivery now: no batteries while the switch is off (a Lowest Device Battery widget shows the
    /// en dash, never an old level or kind) and a real read when it is on. The rest rule keeps a
    /// consumer of nothing but the device battery scheduled until that delivery, then it rests
    /// again. A reading in flight is thrown away (the default interrupting reschedule), so levels
    /// read before an off never arrive after it.
    func deviceBatterySwitchDidChange() {
        deliveries = ReadoutSchedule.restartingDeliveries(deliveries, of: .deviceBattery, in: ledger)
        reschedule()
    }

    /// Follows a power source event for the consumers of the device battery: an accessory that
    /// connects or changes its level arrives as one. Several events while a read runs make one more
    /// read, never an overlapping one. Nothing is read while the switch is off.
    private func deviceBatteriesMayHaveChanged() {
        guard ledger.metrics.contains(.deviceBattery), AccessoryAlertsSettings.readsBattery() else {
            return
        }
        deviceEventPending = true
        guard deviceEventTask == nil else {
            return
        }
        deviceEventTask = Task { [weak self] in
            await self?.deliverDeviceBatteryEvents()
        }
    }

    private func deliverDeviceBatteryEvents() async {
        while deviceEventPending, !Task.isCancelled {
            deviceEventPending = false
            guard let batteries = await readDeviceBatteries(token: nil), !Task.isCancelled else {
                continue
            }
            var sample = ReadoutSample(at: ContinuousClock.now)
            sample.read = [.deviceBattery]
            sample.deviceBatteries = batteries
            deliverEvent(sample, of: .deviceBattery)
        }
        // A cancelled task no longer owns the variable: whoever cancelled it cleared it.
        if !Task.isCancelled {
            deviceEventTask = nil
        }
    }

    /// Reads the accessory batteries through ``AccessoryBatterySource``, only while the Read battery
    /// levels switch is on and this macOS offers the call; otherwise nothing is called and the result
    /// is `nil` (the privacy rule of the switch holds whoever asks, an imported widget included).
    ///
    /// One read is in flight at most: a caller that comes while one runs takes its result. A result
    /// whose tick was replaced meanwhile (`token` is no longer the current generation) is dropped
    /// (M-03). The list stays in memory and is never logged.
    ///
    /// - Parameter token: The generation of the tick that asks, or `nil` for a read that follows an
    ///   event and has no tick to go stale.
    private func readDeviceBatteries(token: Int?) async -> [AccessoryBattery]? {
        guard AccessoryAlertsSettings.readsBattery(), AccessoryBatterySource.isAvailable else {
            return nil
        }
        let batteries: [AccessoryBattery]
        if let running = deviceRead {
            batteries = await running.value
        } else {
            let read = Task { await AccessoryBatterySource.read() }
            deviceRead = read
            batteries = await read.value
            // Only the caller that started the read ends it, so a later read is never cleared.
            deviceRead = nil
        }
        // The switch may have gone off while the read ran: the levels are then not delivered.
        guard AccessoryAlertsSettings.readsBattery() else {
            return nil
        }
        if let token, token != generation {
            return nil
        }
        return batteries
    }

    // MARK: Disk space

    /// Whether the tick reads the precise free space: it carries the disk space and the last
    /// precise read is a minute old or missing.
    private func refreshesDiskSpace(for tick: ReadoutSchedule.Tick) -> Bool {
        tick.metrics.contains(.diskSpace)
            && ReadoutSchedule.refreshesDiskSpace(lastRefresh: preciseDiskSpaceAt, now: .now)
    }

    /// Keeps a precise read, or puts the kept precise figure into a sample that did not read the
    /// space, so a consumer always gets the figure Finder shows and the capacity is asked of the
    /// system once a minute (D-10, L-06).
    private func cachingDiskSpace(of sample: ReadoutSample, refreshed: Bool) -> ReadoutSample {
        guard sample.read.contains(.diskSpace) else {
            return sample
        }
        if refreshed {
            preciseDiskSpace = sample.diskSpace
            preciseDiskSpaceAt = sample.diskSpace == nil ? nil : sample.at
        }
        var cached = sample
        cached.diskSpace = DiskSpaceCache.figure(read: sample.diskSpace, kept: preciseDiskSpace, refreshed: refreshed)
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
            deviceEventTask?.cancel()
            deviceEventTask = nil
            deviceEventPending = false
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
        deviceBatteriesMayHaveChanged()
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
