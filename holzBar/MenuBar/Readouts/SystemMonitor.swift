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
        observerCount = ReadoutSchedule.observers(ledger: ledger, isPaused: isPaused).count
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
            let sample = await SystemSamplers.read(tick.metrics, refreshesDiskSpace: false)
            self?.deliver(sample, for: tick, token: token)
        }
    }

    /// Hands a sample to the consumers of its tick and schedules the next one. A tick that was
    /// replaced or cancelled while it read delivers nothing (T-94-05).
    private func deliver(_ sample: ReadoutSample, for tick: ReadoutSchedule.Tick, token: Int) {
        guard token == generation else {
            return
        }
        samplesTaken += 1
        for id in tick.consumers where sinks[id] != nil {
            deliveries[id] = ReadoutSchedule.Delivery(last: sample.at, count: (deliveries[id]?.count ?? 0) + 1)
        }
        for id in tick.consumers {
            sinks[id]?(sample)
        }
        reschedule()
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
