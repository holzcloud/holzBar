//
//  ThresholdAlertsManager.swift
//  holzBar
//

import Foundation
import Observation
import OSLog

/// The running part of the System alerts module: the one `.background` consumer of the shared
/// ``SystemMonitor``, the Core ``ThresholdEvaluator`` on the rules the settings store, and the
/// alerts as live activities.
///
/// It is an app service and not a hub runtime, so it lives without the Notch hub and a later
/// surface can show its alerts while the hub is off (D-03, D-07). With the module off, or with the
/// module on and every shown rule off, it holds nothing: no consumer is registered with the
/// monitor, no task waits and ``activities`` is empty (``AlertRequestPlan``, MON-08 extended to
/// alerts). With a rule on it registers one consumer, "alerts", and registers it again whenever
/// the request changes. It unregisters while the Mac rests (sleep, screen sleep, lock, session
/// switch) and registers again after the settle delay (``ReadoutVisibility``); the rest ends every
/// firing alert with no done state, and the wake, an unlock and a display change give 30 seconds
/// of quiet (ALRT-04, D-15).
///
/// A firing alert is one ``LiveActivity`` of the module "system-alerts" with the id of its rule;
/// its symbol and tint show the rule and the severity, its short value the latest reading. It stays
/// while the condition holds. When the condition clears it becomes the done state for
/// ``HubActivityBoard/finishedHold`` seconds, under a new id so VoiceOver hears the recovery once,
/// and then goes. A rule, the module or a threshold that no longer holds ends it at once. No sound
/// is played (D-21). The alerts keep values in memory only and log counts only, never a value, a
/// title or a name (D-04, T-95-03).
@MainActor
@Observable
final class ThresholdAlertsManager {
    /// The alerts that are live or finished and still held, as the hub's board takes them.
    private(set) var activities: [LiveActivity] = []

    /// How many alerts are firing now.
    private(set) var firingCount = 0

    /// How many rules are on and watched: the module is on and the rule is shown and switched on.
    private(set) var enabledRuleCount = 0

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var evaluator = ThresholdEvaluator()
    @ObservationIgnored private var visibility = ReadoutVisibility()
    /// The earlier readings, from which the CPU load is made.
    @ObservationIgnored private var baseline = ReadoutBaseline()
    /// What the registered consumer asks for, or `nil` while it is not registered.
    @ObservationIgnored private var registeredRequest: ReadoutRequest?
    /// What the rules ask for now, or `nil` when nothing is to be measured.
    @ObservationIgnored private var desiredRequest: ReadoutRequest?
    @ObservationIgnored private var isModuleOn = false
    @ObservationIgnored private var configLoop: ObservationLoop?
    @ObservationIgnored private var pauseLoop: ObservationLoop?
    /// The one-shot wait for the settle delay after the Mac wakes or unlocks.
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// The one wait for the next hold, clear hold or quiet period to run out.
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "ThresholdAlerts")

    /// What the stored settings decide: whether the module is on and the five rules.
    private struct Config: Equatable {
        var isModuleOn: Bool
        var rules: [ThresholdRule]
    }

    /// The least time before the deadline task wakes, so a deadline already past never becomes a
    /// busy loop.
    private static let minimumWait = Duration.milliseconds(250)

    /// Starts following the module switch and the rules. Registers nothing until a rule is on.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configLoop = ObservationLoop.observe({ [weak appState] in
            Config(
                isModuleOn: appState?.modules.isEnabled(SystemAlertsSettings.moduleID) ?? false,
                rules: appState?.settings.systemAlerts.rules ?? []
            )
        }, onChange: { [weak self] _ in
            self?.configDidChange()
        })
        configDidChange()
    }

    // MARK: Configuration

    /// The module switch or a rule changed: bring the evaluator, the consumer and the tasks in line.
    private func configDidChange() {
        guard let appState else {
            return
        }
        let isOn = appState.modules.isEnabled(SystemAlertsSettings.moduleID)
        let wasOn = isModuleOn
        isModuleOn = isOn
        // Whether this Mac has a battery is asked only once the module is on.
        let hasBattery = isOn && SystemAlertsSettings.hasInternalBattery
        let stored = appState.settings.systemAlerts.rules
        var effective: [ThresholdRule] = []
        if isOn {
            effective = stored.map { rule in
                var rule = rule
                if rule.signal == .macBattery, !hasBattery {
                    rule.isOn = false
                }
                return rule
            }
        }
        if isOn, !wasOn {
            startPauseLoop()
        } else if !isOn, wasOn {
            pauseLoop?.cancel()
            pauseLoop = nil
        }
        handle(evaluator.configure(effective, at: .now))
        let ruleCount = effective.filter(\.isOn).count
        if enabledRuleCount != ruleCount {
            enabledRuleCount = ruleCount
        }
        desiredRequest = AlertRequestPlan.request(rules: stored, isModuleOn: isOn, hasBattery: hasBattery)
        apply(.shown(desiredRequest != nil))
        if visibility.isVisible {
            // A request that changed while registered is asked again; one that did not is kept.
            register()
        }
        if !isOn {
            tearDown()
        }
        rearmDeadline()
        logger.info("System alerts: \(ruleCount, privacy: .public) rule(s) on, \(self.firingCount, privacy: .public) firing")
    }

    /// With the module off nothing is left: no activity, no task.
    private func tearDown() {
        settleTask?.cancel()
        settleTask = nil
        if !activities.isEmpty {
            activities = []
        }
        if firingCount != 0 {
            firingCount = 0
        }
    }

    // MARK: Rest and visibility

    /// Follows whether the Mac rests, only while the module is on.
    private func startPauseLoop() {
        guard let appState else {
            return
        }
        // The visibility rule may have missed a change while no loop ran.
        apply(.paused(appState.systemActivityMonitor.isPaused))
        pauseLoop = ObservationLoop.observe({ [weak appState] in
            appState?.systemActivityMonitor.isPaused ?? false
        }, onChange: { [weak self] isPaused in
            self?.pauseDidChange(isPaused)
        })
    }

    /// The Mac rests or is in use again. A rest ends every firing alert with no done state; use
    /// again gives 30 seconds of quiet, which the settle after it extends (ALRT-04).
    private func pauseDidChange(_ isPaused: Bool) {
        if isPaused {
            handle(evaluator.rest(at: .now))
        } else {
            evaluator.resume(at: .now)
        }
        apply(.paused(isPaused))
        rearmDeadline()
    }

    /// Feeds an event to the visibility rule and does what it says.
    private func apply(_ event: ReadoutVisibility.Event) {
        switch visibility.handle(event, at: .now) {
        case .keep:
            break
        case .register:
            settleTask?.cancel()
            settleTask = nil
            register()
        case .unregister:
            settleTask?.cancel()
            settleTask = nil
            unregister()
        case .waitUntil(let instant):
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                do {
                    try await Task.sleep(until: instant, clock: ContinuousClock())
                } catch {
                    return
                }
                self?.apply(.settleElapsed)
            }
        }
    }

    // MARK: Monitor

    /// Registers the one background consumer with what the rules need, or removes it when nothing
    /// is to be measured. A request that did not change leaves the consumer as it is.
    private func register() {
        guard let appState else {
            return
        }
        guard let request = desiredRequest else {
            unregister()
            return
        }
        guard request != registeredRequest else {
            return
        }
        registeredRequest = request
        baseline.reset()
        appState.systemMonitor.register(AlertRequestPlan.consumerID, kind: .background, request: request) { [weak self] sample in
            self?.receive(sample)
        }
    }

    /// Removes the consumer and forgets the readings, so the next registration starts from a
    /// baseline.
    private func unregister() {
        appState?.systemMonitor.unregister(AlertRequestPlan.consumerID)
        registeredRequest = nil
        baseline.reset()
    }

    /// Takes one sample: each metric it read goes to the evaluator as an observation.
    private func receive(_ sample: ReadoutSample) {
        guard registeredRequest != nil else {
            return
        }
        let now = SuspendingClock.now
        var effects: [ThresholdEvaluator.Effect] = []
        if sample.read.contains(.cpu), let load = baseline.cpuLoad(sample.cpuTicks) {
            // The first sample is only the baseline and has no load.
            effects += evaluator.observe(.fraction(load), for: .cpu, at: now)
        }
        // A metric that was read but has no value is unavailable, which the evaluator ignores.
        if sample.read.contains(.memoryPressure) {
            effects += evaluator.observe(
                sample.memoryPressure.map { .pressure($0) } ?? .unavailable,
                for: .memoryPressure,
                at: now
            )
        }
        if sample.read.contains(.thermal) {
            effects += evaluator.observe(sample.thermal.map { .thermal($0) } ?? .unavailable, for: .thermal, at: now)
        }
        if sample.read.contains(.diskSpace) {
            effects += evaluator.observe(
                sample.diskSpace.map { .freeBytes($0.available) } ?? .unavailable,
                for: .freeDisk,
                at: now
            )
        }
        if sample.read.contains(.power) {
            // The charge is the system's own count, which respects a charge limit (D-14); the rule
            // watches it on battery power only.
            effects += evaluator.observe(
                sample.power.map { .battery(percent: $0.percent, onBattery: $0.state == .onBattery) } ?? .unavailable,
                for: .macBattery,
                at: now
            )
        }
        handle(effects)
        rearmDeadline()
    }

    // MARK: Deadline

    /// Replaces the one wait with a wait for the next instant at which the evaluator has something
    /// to do: a hold that runs out, a clear hold or the end of a quiet period. With nothing
    /// pending there is no task and nothing wakes.
    private func rearmDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard let deadline = evaluator.nextDeadline() else {
            return
        }
        let wake = max(deadline, SuspendingClock.now.advanced(by: Self.minimumWait))
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(until: wake, tolerance: .seconds(1), clock: SuspendingClock())
            } catch {
                return
            }
            self?.deadlineElapsed()
        }
    }

    private func deadlineElapsed() {
        deadlineTask = nil
        handle(evaluator.advance(to: .now))
        rearmDeadline()
    }

    // MARK: Activities

    /// Turns what the evaluator decided into activities.
    private func handle(_ effects: [ThresholdEvaluator.Effect]) {
        let now = Date.now
        for effect in effects {
            switch effect {
            case .fired(let snapshot):
                upsert(activity(for: snapshot, startedAt: now))
            case .updated(let snapshot):
                let startedAt = activities.first { $0.id == snapshot.signal.rawValue }?.startedAt ?? now
                upsert(activity(for: snapshot, startedAt: startedAt))
            case .cleared(let signal):
                clear(signal, at: now)
            case .ended(let signal):
                remove(id: signal.rawValue)
            }
        }
        prune(at: now)
        let firing = evaluator.firing.count
        if firingCount != firing {
            firingCount = firing
        }
        if !effects.isEmpty {
            logger.info("System alerts: \(effects.count, privacy: .public) change(s), \(firing, privacy: .public) firing")
        }
    }

    /// The live activity of a firing alert: its id is its rule's raw value.
    private func activity(for snapshot: AlertSnapshot, startedAt: Date) -> LiveActivity {
        let rule = appState?.settings.systemAlerts.rule(for: snapshot.signal)
            ?? ThresholdRule.defaultRule(for: snapshot.signal)
        return LiveActivity(
            id: snapshot.signal.rawValue,
            moduleID: AlertLook.moduleID,
            kind: .other,
            symbol: AlertLook.symbol(for: snapshot),
            title: AlertTexts.title(for: snapshot),
            detail: AlertTexts.body(for: snapshot, rule: rule),
            priority: AlertLook.priority(for: snapshot.signal),
            startedAt: startedAt,
            tint: AlertLook.tint(for: snapshot.severity),
            announcesItself: false,
            compactValue: AlertLook.shortValue(of: snapshot.observation).map(AlertTexts.shortValue)
        )
    }

    /// Replaces the alert with the done state: a new id, so VoiceOver hears the recovery once, and
    /// the start of the alert it replaces.
    private func clear(_ signal: AlertSignal, at now: Date) {
        let startedAt = activities.first { $0.id == signal.rawValue }?.startedAt ?? now
        remove(id: signal.rawValue)
        upsert(LiveActivity(
            id: Self.recoveredID(of: signal),
            moduleID: AlertLook.moduleID,
            kind: .other,
            symbol: AlertLook.recoveredSymbol,
            title: AlertTexts.recoveredTitle(for: signal),
            priority: AlertLook.priority(for: signal),
            startedAt: startedAt,
            finishedAt: now,
            tint: AlertLook.recoveredTint,
            announcesItself: false,
            compactValue: AlertTexts.normalText
        ))
    }

    private static func recoveredID(of signal: AlertSignal) -> String {
        "\(signal.rawValue).recovered"
    }

    /// Adds an activity, or replaces the one with the same id when it differs.
    private func upsert(_ activity: LiveActivity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else {
            activities.append(activity)
            return
        }
        if activities[index] != activity {
            activities[index] = activity
        }
    }

    private func remove(id: String) {
        guard activities.contains(where: { $0.id == id }) else {
            return
        }
        activities.removeAll { $0.id == id }
    }

    /// Drops the done states the board no longer shows.
    private func prune(at now: Date) {
        let hold = HubActivityBoard.finishedHold * 2
        guard activities.contains(where: { $0.finishedAt.map { now.timeIntervalSince($0) >= hold } ?? false }) else {
            return
        }
        activities.removeAll { $0.finishedAt.map { now.timeIntervalSince($0) >= hold } ?? false }
    }
}
