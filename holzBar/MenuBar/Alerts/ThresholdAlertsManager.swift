//
//  ThresholdAlertsManager.swift
//  holzBar
//

import AppKit
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
/// ``HubActivityBoard/finishedHold`` seconds, under a new id and starting at the moment of
/// recovery, so it widens the closed notch for those seconds however long the alert lasted and
/// VoiceOver hears the recovery once, and then it goes. A rule, the module or a threshold that no longer holds ends it at once. No sound
/// is played (D-21). The alerts keep values in memory only and log counts only, never a value, a
/// title or a name (D-04, T-95-03).
///
/// Every effect of the evaluator reaches the notch exactly once; ``AlertNotificationPlan`` derives
/// from the same effect whether the optional system notification is delivered or withdrawn (D-05,
/// D-22). The manager never names the notification framework: ``UserNotificationCenterNotifier``
/// does, and nothing of it is touched while the module or the System notifications switch is off.
@MainActor
@Observable
final class ThresholdAlertsManager {
    /// The alerts that are live or finished and still held, as the hub's board takes them.
    private(set) var activities: [LiveActivity] = []

    /// How many alerts are firing now.
    private(set) var firingCount = 0

    /// How many rules are on and watched: the module is on and the rule is shown and switched on.
    private(set) var enabledRuleCount = 0

    /// What macOS says about notifications, as far as holzBar has read it. It starts as not
    /// determined and is read only while the module and the System notifications switch are on.
    private(set) var notificationAccess = NotificationAccess.notDetermined

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
    /// The one wait that turns the test alert into its done state.
    @ObservationIgnored private var testTask: Task<Void, Never>?
    /// The alerts' own notch surface, created when an alert first needs it (D-07).
    @ObservationIgnored private var surface: AlertNotchSurface?
    /// Follows the alerts and whether the Notch hub module is on, while the module is on.
    @ObservationIgnored private var surfaceLoop: ObservationLoop?
    /// The only object that touches the notification framework, created when it is first needed.
    @ObservationIgnored private var notifier: UserNotificationCenterNotifier?
    /// The last queued notification operation: deliveries and withdrawals run in order, so a
    /// withdrawal never overtakes the delivery it follows.
    @ObservationIgnored private var notificationTail: Task<Void, Never>?
    /// Reads the permission again whenever holzBar becomes active.
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    /// The one read of the permission, with the one ask when the switch has just gone on.
    @ObservationIgnored private var accessTask: Task<Void, Never>?
    /// The one wait that removes the Test alert's notification again.
    @ObservationIgnored private var testNotificationTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "ThresholdAlerts")

    /// What the stored settings decide: whether the module is on and the five rules.
    private struct Config: Equatable {
        var isModuleOn: Bool
        var rules: [ThresholdRule]
    }

    /// What decides what the notch surface shows: the alerts and whether the Notch hub module is on.
    private struct SurfaceInput: Equatable {
        var activities: [LiveActivity]
        var isHubOn: Bool
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
        // The handler list is append-only, so this registers once. A display change and the settle
        // after a wake give 30 seconds of quiet (D-15).
        appState.systemActivityMonitor.onSettled { [weak self] in
            self?.activityDidSettle()
        }
        configDidChange()
    }

    /// The bar settled after a wake, an unlock, a session switch or a display change: nothing fires
    /// for 30 seconds, and a fire that was due is deferred to their end, not dropped.
    private func activityDidSettle() {
        guard isModuleOn else {
            return
        }
        evaluator.resume(at: .now)
        rearmDeadline()
    }

    // MARK: Test alert

    /// Shows the look of an alert on demand (D-16): the CPU look with 92 percent and the title
    /// "Test alert" for ``DesignTokens/Alert/testSeconds``, then its done state. It is no rule of
    /// the evaluator, so the quiet period, the cooldown and the rate cap do not hold it back, and
    /// it asks for no permission. A second press starts it again. Only while the module is on.
    func showTestAlert() {
        guard isModuleOn else {
            return
        }
        testTask?.cancel()
        let startedAt = Date.now
        deliverTestNotification()
        upsert(LiveActivity(
            id: AlertLook.testID,
            moduleID: AlertLook.moduleID,
            kind: .other,
            symbol: AlertLook.testSymbol,
            title: AlertTexts.testTitle,
            detail: AlertTexts.testBody,
            priority: AlertLook.priority(for: .cpu),
            startedAt: startedAt,
            tint: .amber,
            announcesItself: false,
            compactValue: AlertTexts.shortValue(.percent(AlertLook.testPercent)),
            widenedSeconds: DesignTokens.Alert.widenedSeconds
        ))
        testTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(DesignTokens.Alert.testSeconds))
            } catch {
                return
            }
            self?.finishTestAlert(startedAt: startedAt)
        }
    }

    /// The Test alert as a notification too, while the switch is on and macOS allows it, removed
    /// again after ``DesignTokens/Alert/testNotificationSeconds`` (D-16). It never asks for the
    /// permission: with notifications denied the notch alone shows it.
    private func deliverTestNotification() {
        guard isNotificationSwitchOn, notificationAccess == .allowed else {
            return
        }
        let identifier = AlertNotificationPlan.testIdentifier
        let title = AlertTexts.testTitle
        let body = AlertTexts.testBody
        enqueue { notifier in
            await notifier.deliver(identifier: identifier, title: title, body: body, thread: identifier)
        }
        testNotificationTask?.cancel()
        testNotificationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(DesignTokens.Alert.testNotificationSeconds))
            } catch {
                return
            }
            self?.withdrawNotifications([identifier])
        }
    }

    /// The test alert's done state: the same id and start, so the board drops it after its hold.
    private func finishTestAlert(startedAt: Date) {
        testTask = nil
        guard isModuleOn else {
            return
        }
        upsert(LiveActivity(
            id: AlertLook.testID,
            moduleID: AlertLook.moduleID,
            kind: .other,
            symbol: AlertLook.recoveredSymbol,
            title: AlertTexts.testTitle,
            priority: AlertLook.priority(for: .cpu),
            startedAt: startedAt,
            finishedAt: .now,
            tint: AlertLook.recoveredTint,
            announcesItself: false,
            compactValue: AlertTexts.normalText,
            widenedSeconds: DesignTokens.Alert.widenedSeconds
        ))
        prune(at: .now)
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
            startSurfaceLoop()
            if isNotificationSwitchOn {
                // The module went on with the switch already on: read the permission, never ask.
                startNotifications(asking: false)
            }
        } else if !isOn, wasOn {
            pauseLoop?.cancel()
            pauseLoop = nil
            stopSurface()
            if isNotificationSwitchOn {
                stopNotifications()
            }
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
        testTask?.cancel()
        testTask = nil
        testNotificationTask?.cancel()
        testNotificationTask = nil
        if !activities.isEmpty {
            activities = []
        }
        if firingCount != 0 {
            firingCount = 0
        }
    }

    // MARK: System notifications

    /// Whether the System notifications switch is on.
    private var isNotificationSwitchOn: Bool {
        appState?.settings.systemAlerts.notificationsOn ?? false
    }

    /// Called once before launch finishes (D-05, recorded variant A5): with the module and the
    /// System notifications switch already on, the delegate is installed now so an alert shows
    /// while Settings is in front, and the permission is read, never asked. With either off
    /// nothing of the notification framework is touched. The manager is not set up yet at this
    /// point, so the module switch comes in as an argument.
    func prepareNotificationsAtLaunch(modules: ModuleStore) {
        guard modules.isEnabled(AlertLook.moduleID), SystemAlertsSettings.storedNotificationsOn() else {
            return
        }
        startNotifications(asking: false)
    }

    /// The user switched System notifications on or off. Switching it on is the one moment macOS
    /// is asked for the permission, and only when it has not been asked before (ALRT-03, D-22);
    /// a refusal is never asked again. Switching it off removes every notification of holzBar.
    func notificationsSwitchDidChange(isOn: Bool) {
        if isOn {
            guard isModuleOn else {
                return
            }
            startNotifications(asking: true)
        } else {
            stopNotifications()
        }
    }

    /// Installs the delegate, follows the app becoming active and reads the permission; with
    /// `asking` it also asks for it when macOS has not been asked yet.
    private func startNotifications(asking: Bool) {
        let notifier = ensureNotifier()
        notifier.installDelegate()
        if activationTask == nil {
            activationTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                    await self?.refreshAccess()
                }
            }
        }
        // A read already under way keeps going; one that must ask is never replaced by one that
        // cannot, so the sheet is not lost.
        if accessTask != nil, !asking {
            return
        }
        accessTask?.cancel()
        accessTask = Task { [weak self] in
            var access = await notifier.access()
            if asking, access == .notDetermined {
                access = await notifier.requestPermission()
            }
            // A read that was replaced or stopped meanwhile leaves the state to its successor.
            guard !Task.isCancelled else {
                return
            }
            self?.accessTask = nil
            self?.setAccess(access)
        }
    }

    /// Removes every notification of holzBar and stops following the permission. The delegate
    /// stays: nothing is delivered while the switch or the module is off.
    private func stopNotifications() {
        activationTask?.cancel()
        activationTask = nil
        accessTask?.cancel()
        accessTask = nil
        testNotificationTask?.cancel()
        testNotificationTask = nil
        withdrawNotifications(AlertNotificationPlan.allIdentifiers)
    }

    /// Reads the permission again, so a change made in System Settings shows on return.
    private func refreshAccess() async {
        guard isModuleOn, isNotificationSwitchOn, let notifier else {
            return
        }
        setAccess(await notifier.access())
    }

    private func setAccess(_ access: NotificationAccess) {
        if notificationAccess != access {
            notificationAccess = access
        }
    }

    private func ensureNotifier() -> UserNotificationCenterNotifier {
        if let notifier {
            return notifier
        }
        let notifier = UserNotificationCenterNotifier()
        self.notifier = notifier
        return notifier
    }

    /// Runs a notification operation after the ones queued before it.
    private func enqueue(_ operation: @escaping @MainActor (UserNotificationCenterNotifier) async -> Void) {
        let notifier = ensureNotifier()
        let previous = notificationTail
        notificationTail = Task {
            await previous?.value
            await operation(notifier)
        }
    }

    private func withdrawNotifications(_ identifiers: [String]) {
        enqueue { notifier in
            notifier.withdraw(identifiers: identifiers)
        }
    }

    // MARK: Notch surface

    /// Follows the alerts and the Notch hub module's switch, so the alert reaches the notch while
    /// the hub is off (D-07). Only while the module is on.
    private func startSurfaceLoop() {
        surfaceLoop = ObservationLoop.observe({ [weak self, weak appState] in
            SurfaceInput(activities: self?.activities ?? [], isHubOn: appState?.notchHub.isActive ?? false)
        }, onChange: { [weak self] _ in
            self?.surfaceDidChange()
        })
        surfaceDidChange()
    }

    /// With the module off no surface and no observation is left.
    private func stopSurface() {
        surfaceLoop?.cancel()
        surfaceLoop = nil
        surface?.hide()
        surface = nil
    }

    /// Hands the alerts to the surface. With the Notch hub off the surface draws the widened notch;
    /// with it on the hub does, and the surface shows only where the hub cannot (a bar with no free
    /// span beside the notch), which it works out itself.
    private func surfaceDidChange() {
        guard isModuleOn, let appState else {
            surface?.hide()
            return
        }
        // Created on first need: with nothing to show there is no surface at all.
        if activities.isEmpty, surface == nil {
            return
        }
        let surface = surface ?? AlertNotchSurface(appState: appState)
        self.surface = surface
        surface.update(activities: activities)
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

    /// Turns what the evaluator decided into the actions of the two channels. The notch action is
    /// the same whatever the notification switch and permission say (D-01); the notification
    /// action follows from the same effect (``AlertNotificationPlan``).
    private func handle(_ effects: [ThresholdEvaluator.Effect]) {
        let now = Date.now
        let switchIsOn = isNotificationSwitchOn
        for effect in effects {
            let actions = AlertNotificationPlan.actions(for: effect, notificationsOn: switchIsOn, access: notificationAccess)
            for action in actions {
                perform(action, for: effect, at: now)
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

    /// Does one action of an effect.
    private func perform(_ action: AlertChannelAction, for effect: ThresholdEvaluator.Effect, at now: Date) {
        switch action {
        case .showInNotch:
            switch effect {
            case .fired(let snapshot):
                upsert(activity(for: snapshot, startedAt: now))
            case .updated(let snapshot):
                let startedAt = activities.first { $0.id == snapshot.signal.rawValue }?.startedAt ?? now
                upsert(activity(for: snapshot, startedAt: startedAt))
            case .cleared, .ended:
                break
            }
        case .finishInNotch(let signal):
            clear(signal, at: now)
        case .removeFromNotch(let signal):
            remove(id: signal.rawValue)
        case .deliver(let signal):
            guard case .fired(let snapshot) = effect else {
                return
            }
            let rule = appState?.settings.systemAlerts.rule(for: signal) ?? ThresholdRule.defaultRule(for: signal)
            let identifier = AlertNotificationPlan.identifier(for: signal)
            let thread = AlertNotificationPlan.threadIdentifier(for: signal)
            // Rule names and values only, never a device or an app (T-95-10).
            let title = AlertTexts.title(for: snapshot)
            let body = AlertTexts.body(for: snapshot, rule: rule)
            enqueue { notifier in
                await notifier.deliver(identifier: identifier, title: title, body: body, thread: thread)
            }
        case .withdraw(let signal):
            withdrawNotifications([AlertNotificationPlan.identifier(for: signal)])
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
            compactValue: AlertLook.shortValue(of: snapshot.observation).map(AlertTexts.shortValue),
            widenedSeconds: DesignTokens.Alert.widenedSeconds
        )
    }

    /// Replaces the alert with the done state: a new id, so VoiceOver hears the recovery once, and
    /// a start at the moment of recovery, so it widens the closed notch for its done hold however
    /// long the alert lasted.
    private func clear(_ signal: AlertSignal, at now: Date) {
        remove(id: signal.rawValue)
        upsert(AlertLook.recovery(
            of: signal,
            title: AlertTexts.recoveredTitle(for: signal),
            compactValue: AlertTexts.normalText,
            at: now
        ))
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
