//
//  AutomationManager.swift
//  holzBar
//

import AppKit
import Network
import Observation
import OSLog

/// Runs the automation rules (Phase 8): "when this is true, apply this profile, show these
/// items or turn Zen mode on".
///
/// The decisions are made by ``AutomationEngine``, a pure function. This class only feeds it
/// the facts and carries out what it returns. It never polls: each kind of fact has one
/// observer of a system notification, which exists only while an enabled rule has a
/// condition of that kind. With no enabled rule nothing observes anything.
@MainActor
@Observable
final class AutomationManager {
    /// The rules, in their order. Changing them stores them and updates the observers.
    var rules = [AutomationRule]() {
        didSet {
            guard !isLoading else {
                return
            }
            // A change from outside holds every script until a real event arrives; a change
            // the user makes in holzBar's own pane releases the hold (D-12).
            scriptsAreHeld = changeComesFromOutside
            save()
            itemRulesDidChange()
            sourcesChanged()
            evaluate()
        }
    }

    @ObservationIgnored private let logger = Logger(category: "AutomationManager")
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var engineState = AutomationEngine.State()
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var isSetUp = false

    /// The observers, by the kind of fact they follow.
    @ObservationIgnored private var observers = [AutomationSource: [Task<Void, Never>]]()
    /// Whether this manager has asked ``PowerSourceEvents`` for power source events.
    @ObservationIgnored private var isFollowingPowerSource = false
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var networkKinds: Set<AutomationNetworkKind>?
    @ObservationIgnored private var timeTask: Task<Void, Never>?
    @ObservationIgnored private var storedWiFiMonitor: WiFiNetworkMonitor?
    /// The observer of camera and microphone use, typed loosely so the property exists on every
    /// macOS (it needs 14.2).
    @ObservationIgnored private var captureObserverStorage: AnyObject?
    /// Whether a camera and the microphone are in use, while the observer runs.
    @ObservationIgnored private var captureActivity: (camera: Bool, microphone: Bool)?

    @ObservationIgnored private var audioObserver: AutomationAudioObserver?
    @ObservationIgnored private var bluetoothObserver: AutomationBluetoothObserver?

    /// What holzBar remembers of each item that a rule makes follow a condition, by identity key.
    @ObservationIgnored private var itemRuleMemory = [String: ItemRuleMemory]()
    /// The shown sections as stored, so they are written only when they change.
    @ObservationIgnored private var storedShownSections = [String: Int]()
    @ObservationIgnored private var itemRuleTask: Task<Void, Never>?
    /// Whether holzBar's own move of items is settling. While it is, the item cache may still
    /// show the old sections, and nothing may be taken for a move by hand.
    @ObservationIgnored private var isMovingItems = false
    /// The items holzBar moved whose new section the bar did not show after the move settled.
    /// They are taken as not found for the one pass that follows, never as moved by hand.
    @ObservationIgnored private var unsettledItemKeys = Set<String>()
    /// The items a rule put back, for the hint at the top of Menu Bar Layout. In memory only:
    /// never stored, exported, synced or logged.
    private(set) var itemRuleNotices = [ItemRuleNotice]()

    /// The scripts of the Scripts folder and what the user approved.
    let scriptStore = ScriptStore()
    @ObservationIgnored private let scriptRunner = ScriptRunner()
    /// What the approved scripts answered last, by file name. A script not here is unknown.
    @ObservationIgnored private var scriptResults = [String: Bool]()
    @ObservationIgnored private var lastScriptRun = [String: ContinuousClock.Instant]()
    /// What the last run of each script left behind, by file name: one cleaned line of its
    /// output, how it ended and when. In memory only: never persisted, logged or exported.
    private(set) var lastScriptRuns = [String: ScriptRunRecord]()
    /// What the script widgets want to hear when a real event of the system arrives (D-23). Set
    /// only while the widgets module is on.
    @ObservationIgnored private var systemEventHandler: (@MainActor () -> Void)?

    /// Whether the rule change in progress comes from outside holzBar: from a URL command or a
    /// Shortcut, through ``setRule(withID:enabled:)``.
    @ObservationIgnored private var changeComesFromOutside = false
    /// Whether scripts are held: set by a change from outside, released by the next event of the
    /// system (a notification, a real change of a fact, a time boundary), by "Check now" and by
    /// a change the user makes in the pane. While held, a pass asks no script condition and
    /// starts no script, and a rule that would start waits for that event (D-12, T-11-M5).
    @ObservationIgnored private var scriptsAreHeld = false
    /// The one deferred pass that a profile change asks for; see ``profileDidChange()``.
    @ObservationIgnored private var profileChangeTask: Task<Void, Never>?
    /// The Wi-Fi name last reported, to tell a change from the report that follows a start.
    @ObservationIgnored private var lastWiFiName: String?
    @ObservationIgnored private var hasWiFiReport = false

    /// The activity that keeps the Mac awake while a rule asks for it.
    @ObservationIgnored private var keepAwakeActivity: (any NSObjectProtocol)?

    /// The reader of the Wi-Fi network name. It exists from the first time it is needed.
    var wifiMonitor: WiFiNetworkMonitor {
        if let storedWiFiMonitor {
            return storedWiFiMonitor
        }
        let monitor = WiFiNetworkMonitor()
        monitor.onChange = { [weak self] in
            self?.wifiReported()
        }
        storedWiFiMonitor = monitor
        return monitor
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        scriptStore.performSetup()
        load()
        isSetUp = true
        sourcesChanged()
        evaluate()
        if rules.contains(where: { $0.isEnabled && ItemVisibility.itemKey(of: $0) != nil }) {
            // The bar is not read yet: look at the items once the cache has caught up.
            scheduleItemRuleEvaluation()
        }
    }

    // MARK: Storage

    /// Loads the rules: the ones of the settings and, from this Mac's script store, the ones that
    /// use a script (D-05). A rule that uses a script found in the settings is left out, and the
    /// settings are saved once without it; the first time, the script rules and approvals of
    /// 0.0.8-beta1 and beta2 move into the store (D-14).
    private func load() {
        isLoading = true
        defer {
            isLoading = false
        }
        var decoded = [AutomationRule]()
        if
            let data = Defaults.data(forKey: .automationRules),
            let stored = try? JSONDecoder().decode([AutomationRule].self, from: data)
        {
            decoded = AutomationRule.validated(stored)
        }
        scriptStore.adoptLegacyData(rules: decoded.filter(\.usesScript), order: decoded.map(\.id))
        rules = AutomationRuleStorage.merge(
            settings: decoded,
            local: scriptStore.scriptRules,
            order: scriptStore.ruleOrder
        )
        let leftOut = AutomationRuleStorage.droppedScriptRuleCount(settings: decoded)
        let collisions = AutomationRuleStorage.collidingRuleCount(settings: decoded, local: scriptStore.scriptRules)
        if leftOut > 0 {
            logger.notice(
                "Left out \(leftOut, privacy: .public) rules that use a script from the settings; scripts are set up only on this Mac"
            )
        }
        if collisions > 0 {
            // The rule of this Mac wins; the settings copy goes (T-11-H1).
            logger.notice(
                "Kept \(collisions, privacy: .public) script rules of this Mac over rules of the settings with the same identifier"
            )
        }
        if leftOut > 0 || collisions > 0 {
            // The settings no longer hold them.
            save()
        }
        migrateLegacyRevealRules()
        loadItemRuleMemory()
    }

    /// Reads the shown sections of the items that rules control. The stored value is
    /// untrusted: any process of the user can write the defaults.
    private func loadItemRuleMemory() {
        let stored = Defaults.dictionary(forKey: .itemRuleShownSections) as? [String: Int] ?? [:]
        itemRuleMemory = ItemVisibility.restoredMemory(from: stored, ruleKeys: ItemVisibility.ruleKeys(in: rules))
        storedShownSections = ItemVisibility.persistableShownSections(
            itemRuleMemory,
            ruleKeys: ItemVisibility.ruleKeys(in: rules)
        )
    }

    /// Stores the shown sections of the items that rules control, when they changed. They stay
    /// on this Mac (a local-only key), so after a restart an item returns to the section it had.
    private func persistShownSections() {
        let wanted = ItemVisibility.persistableShownSections(itemRuleMemory, ruleKeys: ItemVisibility.ruleKeys(in: rules))
        guard wanted != storedShownSections else {
            return
        }
        storedShownSections = wanted
        if wanted.isEmpty {
            Defaults.removeObject(forKey: .itemRuleShownSections)
        } else {
            Defaults.set(wanted, forKey: .itemRuleShownSections)
        }
    }

    /// Takes over the two fixed rules of 0.0.7 and earlier (low battery, offline) as rules of
    /// the engine, once, and forgets the old setting.
    private func migrateLegacyRevealRules() {
        guard let stored = Defaults.dictionary(forKey: .revealRules) else {
            return
        }
        let migrated = LegacyRevealRules.rules(
            from: stored,
            batteryName: String(localized: "When the battery is low"),
            offlineName: String(localized: "When the network connection is lost")
        )
        if !migrated.isEmpty {
            rules = AutomationRule.validated(rules + migrated)
            save()
            logger.notice("Moved \(migrated.count, privacy: .public) old reveal rules into the automation rules")
        }
        Defaults.removeObject(forKey: .revealRules)
    }

    /// Saves the rules in two places: the ones that use a script, with the order of all of them,
    /// in the script store of this Mac, and the others in the settings. The store is written
    /// first, and the settings drop the rules that use a script only once the store holds them
    /// on disk: a failed write, or a crash between the two writes, loses no rule. Until then the
    /// settings keep them, and an export and an import still carry none (T-11-H1).
    private func save() {
        let parts = AutomationRuleStorage.split(rules)
        let isStored = scriptStore.setScriptRules(parts.local, order: parts.order)
        let forSettings = isStored ? parts.settings : rules
        if let data = try? JSONEncoder().encode(forSettings) {
            Defaults.set(data, forKey: .automationRules)
        }
    }

    // MARK: Observers

    /// Starts the observers the enabled rules need and stops the others.
    private func sourcesChanged() {
        guard isSetUp else {
            return
        }
        let needed = AutomationRule.observedSources(of: rules)
        for source in AutomationSource.allCases {
            if needed.contains(source) {
                start(source)
            } else {
                stop(source)
            }
        }
        if needed.contains(.time) {
            // The windows changed, so the next boundary may have too.
            restartTimeTask()
        }
    }

    private func start(_ source: AutomationSource) {
        guard observers[source] == nil else {
            return
        }
        switch source {
        case .power:
            startPowerSource()
            observe(source, notifications: [(NotificationCenter.default, .powerSourcesDidChange)])
        case .lowPowerMode:
            observe(source, notifications: [(NotificationCenter.default, .NSProcessInfoPowerStateDidChange)])
        case .runningApps:
            let center = NSWorkspace.shared.notificationCenter
            observe(
                source,
                notifications: [
                    (center, NSWorkspace.didLaunchApplicationNotification),
                    (center, NSWorkspace.didTerminateApplicationNotification),
                ]
            )
        case .frontmostApp:
            observe(
                source,
                notifications: [(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification)]
            )
        case .displays:
            observe(source, notifications: [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)])
        case .time:
            // The time task runs the check at each boundary; these notifications move the
            // boundary: a new day, a changed clock or time zone, and the end of sleep.
            observe(
                source,
                notifications: [
                    (NotificationCenter.default, .NSCalendarDayChanged),
                    (NotificationCenter.default, .NSSystemClockDidChange),
                    (NotificationCenter.default, .NSSystemTimeZoneDidChange),
                    (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
                ],
                restartsTime: true
            )
        case .network:
            startPathMonitor()
        case .wifi:
            wifiMonitor.start()
        case .capture:
            startCaptureObserver()
        case .audioOutput:
            let observer = AutomationAudioObserver()
            observer.onChange = { [weak self] in
                self?.scriptsAreHeld = false
                self?.evaluate()
                self?.systemEventHandler?()
            }
            audioObserver = observer
            observer.start()
        case .bluetooth:
            let observer = AutomationBluetoothObserver()
            observer.onChange = { [weak self] in
                self?.scriptsAreHeld = false
                self?.evaluate()
                self?.systemEventHandler?()
            }
            bluetoothObserver = observer
            observer.start()
        case .scripts:
            // A script condition is asked when the events of power, network, apps and displays
            // arrive (``AutomationRule/observedSources(of:)``) and after the Mac wakes; never
            // by a timer of its own.
            observe(
                source,
                notifications: [(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)]
            )
        }
    }

    private func stop(_ source: AutomationSource) {
        for task in observers.removeValue(forKey: source) ?? [] {
            task.cancel()
        }
        switch source {
        case .power:
            stopPowerSource()
        case .time:
            timeTask?.cancel()
            timeTask = nil
        case .network:
            pathMonitor?.cancel()
            pathMonitor = nil
            networkKinds = nil
        case .wifi:
            storedWiFiMonitor?.stop()
            hasWiFiReport = false
            lastWiFiName = nil
        case .capture:
            stopCaptureObserver()
        case .audioOutput:
            audioObserver?.stop()
            audioObserver = nil
        case .bluetooth:
            bluetoothObserver?.stop()
            bluetoothObserver = nil
        case .lowPowerMode, .runningApps, .frontmostApp, .displays, .scripts:
            break
        }
    }

    /// Follows notifications and checks the rules for each one.
    private func observe(
        _ source: AutomationSource,
        notifications: [(NotificationCenter, Notification.Name)],
        restartsTime: Bool = false
    ) {
        observers[source] = notifications.map { center, name in
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    if restartsTime {
                        self?.restartTimeTask()
                    }
                    // A notification is an event of the system: scripts are no longer held.
                    self?.scriptsAreHeld = false
                    self?.evaluate()
                    self?.systemEventHandler?()
                }
            }
        }
    }

    /// The power source events are one run loop source for the whole app, shared with the
    /// widgets; this manager holds one use of it while a rule needs the power source.
    private func startPowerSource() {
        guard !isFollowingPowerSource else {
            return
        }
        isFollowingPowerSource = true
        PowerSourceEvents.shared.begin()
    }

    private func stopPowerSource() {
        guard isFollowingPowerSource else {
            return
        }
        isFollowingPowerSource = false
        PowerSourceEvents.shared.end()
    }

    /// `NWPathMonitor` only watches the state of the network paths; it never opens a
    /// connection or sends anything.
    private func startPathMonitor() {
        guard pathMonitor == nil else {
            return
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            var kinds = Set<AutomationNetworkKind>()
            if path.status != .satisfied {
                kinds.insert(.offline)
            }
            if path.usesInterfaceType(.wifi) {
                kinds.insert(.wifi)
            }
            if path.usesInterfaceType(.wiredEthernet) {
                kinds.insert(.ethernet)
            }
            if path.isExpensive {
                kinds.insert(.expensive)
            }
            // A tunnel interface (`utun`, `ipsec`, `ppp`) carries the traffic: a VPN that sends
            // everything through it. A VPN that only routes some networks is not seen.
            if path.usesInterfaceType(.other) {
                kinds.insert(.vpn)
            }
            Task { @MainActor in
                self?.networkChanged(kinds, from: monitor)
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    private func networkChanged(_ kinds: Set<AutomationNetworkKind>, from monitor: NWPathMonitor) {
        // An update of a monitor that was stopped meanwhile is stale.
        guard monitor === pathMonitor else {
            return
        }
        // The first report after a start is the state, not an event.
        let isEvent = networkKinds.map { $0 != kinds } ?? false
        if isEvent {
            scriptsAreHeld = false
        }
        networkKinds = kinds
        evaluate()
        if isEvent {
            systemEventHandler?()
        }
    }

    /// The Wi-Fi monitor reported. It does so once when it starts and again for a change of the
    /// name or of the permission; only a changed name is an event.
    private func wifiReported() {
        let name = storedWiFiMonitor?.networkName
        let isEvent = hasWiFiReport && name != lastWiFiName
        if isEvent {
            scriptsAreHeld = false
        }
        hasWiFiReport = true
        lastWiFiName = name
        evaluate()
        if isEvent {
            systemEventHandler?()
        }
    }

    /// Starts following camera and microphone use. Before macOS 14.2 the facts stay unknown, so
    /// the conditions never hold.
    private func startCaptureObserver() {
        guard #available(macOS 14.2, *), captureObserverStorage == nil else {
            return
        }
        let observer = AutomationCaptureObserver()
        observer.onChange = { [weak self] isCameraInUse, isMicrophoneInUse in
            guard let self else {
                return
            }
            var isEvent = false
            if let previous = captureActivity, previous != (isCameraInUse, isMicrophoneInUse) {
                scriptsAreHeld = false
                isEvent = true
            }
            captureActivity = (isCameraInUse, isMicrophoneInUse)
            evaluate()
            if isEvent {
                systemEventHandler?()
            }
        }
        captureObserverStorage = observer
        captureActivity = (false, false)
        observer.start()
    }

    private func stopCaptureObserver() {
        if #available(macOS 14.2, *), let observer = captureObserverStorage as? AutomationCaptureObserver {
            observer.stop()
        }
        captureObserverStorage = nil
        captureActivity = nil
    }

    /// Arms one timer for the next start or end of a time span; nothing runs in between.
    private func restartTimeTask() {
        timeTask?.cancel()
        timeTask = nil
        let windows = AutomationRule.timeWindows(of: rules)
        guard !windows.isEmpty else {
            return
        }
        timeTask = Task { [weak self] in
            while !Task.isCancelled {
                let components = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
                let seconds = Double((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
                guard let delay = AutomationSchedule.secondsUntilNextBoundary(of: windows, from: seconds) else {
                    return
                }
                // A moment past the boundary, so the check sees the new minute.
                try? await Task.sleep(for: .seconds(delay + 1))
                guard !Task.isCancelled else {
                    return
                }
                self?.scriptsAreHeld = false
                self?.evaluate()
            }
        }
    }

    // MARK: Facts

    /// The current facts, for the kinds the enabled rules need. The others stay unknown.
    private func currentFacts() -> AutomationFacts {
        let needed = AutomationRule.sources(of: rules)
        var facts = AutomationFacts()
        if needed.contains(.power) {
            let power = Self.powerFacts()
            facts.powerSource = power.source
            facts.batteryPercent = power.percent
        }
        if needed.contains(.lowPowerMode) {
            facts.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        if needed.contains(.runningApps) {
            facts.runningApps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        if needed.contains(.frontmostApp) {
            facts.frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        if needed.contains(.time) {
            let components = Calendar.current.dateComponents([.hour, .minute, .weekday], from: .now)
            facts.minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            facts.weekday = components.weekday
        }
        if needed.contains(.displays) {
            facts.connectedDisplays = LayoutProfiles.connectedDisplayUUIDs()
        }
        if needed.contains(.network) {
            facts.networkKinds = networkKinds
        }
        if needed.contains(.wifi) {
            facts.wifiName = storedWiFiMonitor?.networkName
        }
        if needed.contains(.capture), let captureActivity {
            facts.isCameraInUse = captureActivity.camera
            facts.isMicrophoneInUse = captureActivity.microphone
        }
        if needed.contains(.audioOutput) {
            facts.audioOutputName = AudioOutputDevices.defaultOutputName()
        }
        if needed.contains(.bluetooth) {
            facts.connectedBluetoothDevices = AutomationBluetoothObserver.connectedNames()
        }
        facts.scriptResults = scriptResults
        return facts
    }

    /// The power source and the level of the internal battery. A Mac without a battery runs
    /// on its adapter and has no level. The reading is shared with the widgets.
    private static func powerFacts() -> (source: AutomationPowerSource?, percent: Int?) {
        switch PowerSources.read() {
        case .unreadable:
            return (nil, nil)
        case .noBattery:
            return (.adapter, nil)
        case .battery(let battery):
            return (battery.isOnBattery ? .battery : .adapter, battery.percent)
        }
    }

    // MARK: Evaluating

    /// Checks the rules against the current facts and carries out what changed. While scripts
    /// are held (after a change from a URL command or a Shortcut), no script condition is asked
    /// and no script starts: the stored answers are used, and the engine is told so.
    private func evaluate() {
        guard isSetUp, let appState else {
            return
        }
        // With no enabled rule and nothing remembered there is nothing to do.
        guard rules.contains(where: \.isEnabled) || !engineState.active.isEmpty else {
            return
        }
        let allowsScripts = !scriptsAreHeld
        if allowsScripts {
            refreshScriptResults()
        }
        let facts = currentFacts()
        followItemRules(facts: facts)
        let result = AutomationEngine.evaluate(
            rules: rules,
            facts: facts,
            context: AutomationEngine.Context(
                currentProfile: appState.profiles.currentProfileName,
                currentMood: appState.appearanceManager.currentMoodName,
                isZenOn: appState.menuBarManager.zenMode.isManual,
                isKeepAwakeOn: keepAwakeActivity != nil
            ),
            state: engineState,
            allowsScripts: allowsScripts
        )
        engineState = result.state
        for effect in result.effects {
            perform(effect, with: appState, allowsScripts: allowsScripts)
        }
    }

    // MARK: Scripts

    /// Asks the approved scripts that rules use as conditions, at most every 30 seconds each:
    /// they are checked when other events arrive and by ``checkScriptsNow()``, never by a
    /// timer of their own.
    private func refreshScriptResults() {
        var names = Set<String>()
        for clause in rules.filter(\.isEnabled).flatMap(\.clauses) {
            if case .scriptSucceeds(let name) = clause.condition {
                names.insert(name)
            }
        }
        scriptResults = scriptResults.filter { names.contains($0.key) }
        for name in names {
            let now = ContinuousClock.now
            guard ScriptLimits.isConditionDue(lastAsked: lastScriptRun[name], now: now) else {
                continue
            }
            lastScriptRun[name] = now
            Task { [weak self] in
                guard let self else {
                    return
                }
                let report = await scriptRunner.run(
                    name,
                    event: .check,
                    timeLimit: scriptStore.timeLimit(for: name),
                    folder: scriptStore.folderURL,
                    store: scriptStore
                )
                if let record = report.record {
                    lastScriptRuns[name] = record
                }
                switch report.outcome {
                case .succeeded: scriptResults[name] = true
                case .failed, .timedOut: scriptResults[name] = false
                case .notAllowed, .rateLimited: scriptResults.removeValue(forKey: name)
                case .busy: break // the script still runs: its last answer stands
                }
                evaluate()
            }
        }
    }

    /// Asks every script a rule uses now, without waiting for the next event. This is the
    /// user's own action in holzBar, so it also releases the hold of a change from outside.
    func checkScriptsNow() {
        scriptsAreHeld = false
        lastScriptRun.removeAll()
        scriptStore.refresh()
        evaluate()
    }

    /// Runs the scripts one after another, each with its own time limit, and keeps what each
    /// left behind. The runner decides for each one whether it may run; one that is not
    /// approved is skipped (its row says it needs approval), and one that is busy or over the
    /// rate limit is skipped and shown as such, so a dropped start or end script is not
    /// silent. It stops starting scripts when the calling task is cancelled.
    ///
    /// - Parameters:
    ///   - names: The script file names, in order.
    ///   - event: What happened.
    ///   - totalSeconds: The most time all of them may take together, or `nil` for no overall
    ///     limit. Each script gets its own limit or what is left, and scripts that find no time
    ///     left are not started (profile hooks, WR-07).
    func runScripts(_ names: [String], event: ScriptEvent, totalSeconds: Int? = nil) async {
        let clock = ContinuousClock()
        let start = clock.now
        for name in names {
            guard !Task.isCancelled else {
                return
            }
            var timeLimit = scriptStore.timeLimit(for: name)
            if let totalSeconds {
                let left = Duration.seconds(totalSeconds) - (clock.now - start)
                guard let allowed = ProfileHooks.timeLimit(
                    ownLimit: timeLimit,
                    remainingSeconds: Int(left.components.seconds)
                ) else {
                    logger.notice("The time for script hooks is used up; the rest are skipped")
                    return
                }
                timeLimit = allowed
            }
            let report = await scriptRunner.run(
                name,
                event: event,
                timeLimit: timeLimit,
                folder: scriptStore.folderURL,
                store: scriptStore
            )
            if let record = report.record {
                lastScriptRuns[name] = record
            } else if let reason = ScriptSkipReason(outcome: report.outcome) {
                lastScriptRuns[name] = ScriptRunRecord(date: .now, termination: .skipped(reason), displayLine: "")
            }
        }
    }

    /// Runs the script of a script widget once, with the event `widget-refresh`, under the same
    /// runner and gate as every script: the file is checked again, its full SHA-256 must be the
    /// one the user approved, the time limit and one run at a time apply, and widget runs have a
    /// limit of ten a minute of their own (D-23).
    ///
    /// What the run left behind is kept like that of any script, so the Scripts section shows it,
    /// skipped runs included.
    ///
    /// - Parameter name: The file name in the scripts folder, as bound in the script store.
    /// - Returns: How the run ended, and the line it printed when it started.
    func runWidgetScript(named name: String) async -> ScriptRunReport {
        let report = await scriptRunner.run(
            name,
            event: .widgetRefresh,
            timeLimit: scriptStore.timeLimit(for: name),
            folder: scriptStore.folderURL,
            store: scriptStore
        )
        if let record = report.record {
            lastScriptRuns[name] = record
        } else if let reason = ScriptSkipReason(outcome: report.outcome) {
            lastScriptRuns[name] = ScriptRunRecord(date: .now, termination: .skipped(reason), displayLine: "")
        }
        return report
    }

    /// Sets what runs after each engine pass that a real event of the system caused: a
    /// notification (power source, wake, apps, displays, the clock), a changed network or Wi-Fi
    /// name, or camera and microphone use. It never runs for a change from outside holzBar (a URL
    /// command or a Shortcut), which holds scripts and is no event (D-12, T-12-28).
    ///
    /// The engine follows only the facts that an enabled rule needs, so with no such rule it has
    /// no events to give; the widgets then run on a reveal and on a click only. Pass `nil` to
    /// stop.
    func onSystemEvent(_ handler: (@MainActor () -> Void)?) {
        systemEventHandler = handler
    }

    /// Starts the scripts in a task of their own and does not wait for them.
    func startScripts(_ names: [String], event: ScriptEvent) {
        guard !names.isEmpty else {
            return
        }
        Task { [weak self] in
            await self?.runScripts(names, event: event)
        }
    }

    /// A profile was applied by the user, a hotkey, a rule or a display or Space binding: the
    /// profile-change event of D-04. It asks the script conditions once, on the next turn of the
    /// main actor, and only when a rule has one. The turn keeps an apply that the engine itself
    /// performed from re-entering ``evaluate()`` while its effects are carried out (T-11-L1).
    /// An apply from a URL command, a Shortcut or the Focus filter never calls this (D-12).
    func profileDidChange() {
        guard
            isSetUp,
            profileChangeTask == nil,
            AutomationRule.observedSources(of: rules).contains(.scripts)
        else {
            return
        }
        profileChangeTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else {
                return
            }
            profileChangeTask = nil
            evaluate()
        }
    }

    // MARK: Items that follow a condition

    /// The rules of the kind "show it only while …" that are on, with what they say now.
    private func itemFollows(facts: AutomationFacts) -> [(itemKey: String, holds: Bool?, hiding: Int)] {
        rules.compactMap { ItemVisibility.follow(of: $0, facts: facts) }
    }

    /// The section of each item in the item cache, by identity key, without the items whose
    /// move has not settled.
    private func itemSectionsInCache(of appState: AppState) -> [String: Int] {
        let itemManager = appState.itemManager
        var sections = [String: Int]()
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.itemCache[section] where !item.isControlItem {
                let key = itemManager.identityKey(for: item)
                if !unsettledItemKeys.contains(key) {
                    sections[key] = section.profileIndex
                }
            }
        }
        return sections
    }

    /// Looks at the items that follow a rule and, when one has to move or its memory changes,
    /// acts on it after a hold of three seconds so a flapping condition (a VPN that
    /// reconnects, Wi-Fi that roams) does not move an item every second. The facts and the
    /// sections are read again after the hold, and nothing moves while the user drags an item.
    private func followItemRules(facts: AutomationFacts) {
        // A pending pass reads everything again when it runs, so it is not postponed. While
        // holzBar's own move settles the cache may show the old sections.
        guard itemRuleTask == nil, !isMovingItems, let appState else {
            return
        }
        let follows = itemFollows(facts: facts)
        guard !follows.isEmpty else {
            return
        }
        let decisions = ItemVisibility.decisions(
            follows: follows,
            actual: itemSectionsInCache(of: appState),
            memory: itemRuleMemory
        )
        let hasWork = decisions.contains { key, decision in
            decision.moveTo != nil || decision.memory != (itemRuleMemory[key] ?? ItemRuleMemory())
        }
        if hasWork {
            scheduleItemRuleEvaluation()
        }
    }

    /// Arms the one-shot hold of three seconds, then looks at the items that follow a rule.
    private func scheduleItemRuleEvaluation() {
        guard itemRuleTask == nil else {
            return
        }
        itemRuleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else {
                return
            }
            await moveItems()
            itemRuleTask = nil
            // The conditions may have changed meanwhile, and a drag may have held the pass back.
            followItemRules(facts: currentFacts())
            unsettledItemKeys.removeAll()
        }
    }

    /// The user moved items by hand (Menu Bar Layout, the keyboard, VoiceOver, undo, a Command-drag,
    /// the drag module): asks for one look at the items that follow a rule, after the hold, once
    /// the item cache has caught up. It adds no timer: the move is the event.
    func itemsWereArrangedByHand() {
        guard isSetUp, !isMovingItems, rules.contains(where: { $0.isEnabled && ItemVisibility.itemKey(of: $0) != nil }) else {
            return
        }
        scheduleItemRuleEvaluation()
    }

    /// Carries out the decisions for the items that follow a rule: moves the items that have to
    /// move, remembers the sections, and tells the user about every move by hand it undid.
    private func moveItems() async {
        guard let appState, !appState.profiles.isLayoutDragInProgress else {
            return
        }
        // The bar is read once more, so the sections below are the real ones.
        await appState.itemManager.cacheItemsRegardless()
        guard !appState.profiles.isLayoutDragInProgress else {
            return
        }
        let decisions = ItemVisibility.decisions(
            follows: itemFollows(facts: currentFacts()),
            actual: itemSectionsInCache(of: appState),
            memory: itemRuleMemory
        )
        var changes = [String: Int]()
        for (key, decision) in decisions {
            itemRuleMemory[key] = decision.memory
            if let section = decision.moveTo {
                changes[key] = section
            }
            if let revert = decision.revert {
                addItemRuleNotice(forKey: key, putBackIn: revert.putBack, appState: appState)
            }
        }
        persistShownSections()
        guard !changes.isEmpty else {
            return
        }
        appState.snapshots.willApplyRules()
        // On macOS 27 the layout is keyed by application, and a widget by its autosave name. The
        // key comes from the item itself (`layoutKey27`); the part of the rule's key before the
        // colon is only the fallback, and holzBar's own bundle never becomes a key.
        var applicationSections = [String: Int]()
        for (key, section) in changes {
            if let layoutKey = layoutKeys(forItemKeys: [key]).first {
                applicationSections[layoutKey] = section
            }
        }
        logger.notice("An automation rule moves \(changes.count, privacy: .public) items")
        // Until the move has settled and the bar was read, the cache may show the old sections,
        // and an item there must not be taken for one the user moved by hand.
        isMovingItems = true
        defer {
            isMovingItems = false
        }
        await appState.profiles.applyLayout(of: LayoutProfile(
            name: "",
            itemSections: changes,
            applicationSections: applicationSections
        ))?.value
        // The cache refuses a read within a second of a move.
        try? await Task.sleep(for: .milliseconds(1500))
        await appState.itemManager.cacheItemsRegardless()
        let settled = itemSectionsInCache(of: appState)
        unsettledItemKeys = Set(changes.filter { settled[$0.key] != $0.value }.keys)
    }

    /// Tells the user that a rule put an item back: one notice per item, the newest first.
    private func addItemRuleNotice(forKey key: String, putBackIn section: Int, appState: AppState) {
        let itemManager = appState.itemManager
        let name = itemManager.itemCache.managedItems.first { itemManager.identityKey(for: $0) == key }?.displayName
        itemRuleNotices = ItemRuleNotices.adding(
            ItemRuleNotice(
                itemKey: key,
                itemName: ItemRuleNotices.cleanedName(name ?? "", fallback: String(localized: "A menu bar item")),
                putBackIn: section
            ),
            to: itemRuleNotices
        )
        logger.notice("An automation rule put an item back after a move by hand")
    }

    /// Dismisses the notice of an item.
    func dismissItemRuleNotice(forKey key: String) {
        itemRuleNotices.removeAll { $0.itemKey == key }
    }

    /// The rules changed: forgets what holzBar knows of items whose rule is gone or off, and
    /// the notices of items that no rule controls any more.
    private func itemRulesDidChange() {
        let controlled = controlledItemKeys
        let ruleKeys = ItemVisibility.ruleKeys(in: rules)
        for key in Array(itemRuleMemory.keys) {
            if !ruleKeys.contains(key) {
                itemRuleMemory.removeValue(forKey: key)
            } else if !controlled.contains(key) {
                // A rule that is off leaves the item where the user puts it.
                itemRuleMemory[key]?.applied = nil
            }
        }
        let kept = ItemRuleNotices.keeping(itemRuleNotices, controlled: controlled)
        if kept != itemRuleNotices {
            itemRuleNotices = kept
        }
        persistShownSections()
    }

    /// Carries out one effect of the engine. `allowsScripts` is false for a pass that a change
    /// from outside caused: a profile such a pass applies runs no hooks (D-12, T-11-M5).
    private func perform(_ effect: AutomationEngine.Effect, with appState: AppState, allowsScripts: Bool) {
        switch effect {
        case .applyProfile(let name):
            logger.notice("An automation rule applies a profile")
            if allowsScripts {
                appState.profiles.apply(named: name)
            } else {
                // A pass that a URL command or a Shortcut caused: no hook runs for its profile.
                appState.profiles.apply(named: name, runsHooks: false)
            }
        case .applyMood(let name):
            logger.notice("An automation rule applies a mood")
            appState.appearanceManager.applyMood(named: name)
        case .showSection(let section):
            reveal(section == .alwaysHidden ? .alwaysHidden : .hidden)
        case .setZen(let isOn):
            logger.notice("An automation rule turns Zen mode \(isOn ? "on" : "off", privacy: .public)")
            appState.menuBarManager.setManualZenMode(isOn)
        case .setKeepAwake(let isOn):
            setKeepAwake(isOn)
        case .runScript(let name, let event):
            startScripts([name], event: event)
        }
    }

    /// Shows a section for the "temporarily shown item" interval, then hides it again, unless
    /// Zen mode is on.
    private func reveal(_ name: MenuBarSection.Name) {
        guard
            let appState,
            let section = appState.menuBarManager.section(withName: name),
            section.isHidden
        else {
            return
        }
        guard appState.menuBarManager.zenMode.allows(.revealRule) else {
            logger.notice("An automation rule does not show hidden items: Zen mode")
            return
        }
        logger.notice("An automation rule shows hidden items")
        section.show(bypassingLock: true)
        appState.menuBarManager.showOnHoverAllowed = false
        let interval = appState.settings.advanced.tempShowInterval
        Task {
            try? await Task.sleep(for: .seconds(interval))
            if !section.isHidden {
                section.hide()
            }
        }
    }

    /// Whether holzBar keeps the Mac awake now.
    var isKeepAwakeOn: Bool {
        keepAwakeActivity != nil
    }

    /// Keeps the Mac awake or lets it sleep, as the user asked (its hotkey or the palette).
    func toggleKeepAwake() {
        setKeepAwake(!isKeepAwakeOn)
    }

    /// Keeps the Mac and its display awake, or lets them sleep. The activity is a hold on idle
    /// sleep only; the user can still sleep the Mac, and it ends when holzBar quits.
    private func setKeepAwake(_ isOn: Bool) {
        if isOn {
            guard keepAwakeActivity == nil else {
                return
            }
            logger.notice("holzBar keeps the Mac awake")
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "holzBar keeps the Mac awake"
            )
        } else if let activity = keepAwakeActivity {
            logger.notice("holzBar lets the Mac sleep again")
            ProcessInfo.processInfo.endActivity(activity)
            keepAwakeActivity = nil
        }
    }

    // MARK: Editing

    /// Adds a new rule, switched off, and returns its identifier.
    @discardableResult
    func addRule(named name: String, profileName: String?) -> UUID {
        let action: AutomationAction = profileName.map(AutomationAction.applyProfile) ?? .showSection(.hidden)
        let rule = AutomationRule(
            name: name,
            isEnabled: false,
            clauses: [AutomationClause(condition: .power(.battery))],
            action: action
        )
        rules.append(rule)
        return rule.id
    }

    /// The rule with the given name: an exact match first, then one that differs only in
    /// case and accents.
    func rule(named name: String) -> AutomationRule? {
        rules.first { $0.name == name }
            ?? rules.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// The rules that are true now and have acted.
    var activeRules: [AutomationRule] {
        rules.filter { engineState.active.contains($0.id) }
    }

    /// Turns a rule on or off. This is the entry point of the `holzbar://` URL commands and of
    /// Shortcuts; the pane changes rules through its bindings instead. A change made here runs
    /// no script: no end script runs, no script condition is asked, and a rule that runs a
    /// script waits for the next event of the system. A rule that uses a script is never turned
    /// on from here (D-12).
    func setRule(withID id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }), rules[index].isEnabled != enabled else {
            return
        }
        // Whatever the caller checked, nothing from outside turns on a rule that uses a script:
        // the rule may have changed while a question was open (D-12, T-11-M5).
        guard !(enabled && rules[index].usesScript) else {
            logger.notice("Ignored: a rule that uses a script is turned on only in the settings")
            return
        }
        changeComesFromOutside = true
        defer {
            changeComesFromOutside = false
        }
        rules[index].isEnabled = enabled
    }

    func removeRule(withID id: UUID) {
        if let rule = rules.first(where: { $0.id == id }), let key = ItemVisibility.itemKey(of: rule) {
            // The next rule for the item starts from nothing.
            itemRuleMemory.removeValue(forKey: key)
        }
        rules.removeAll { $0.id == id }
    }

    // MARK: Item rules

    /// The identity keys of the items that rules control now.
    var controlledItemKeys: Set<String> {
        ItemVisibility.controlledKeys(in: rules)
    }

    /// The rule that shows the item with the given identity key only while a condition holds.
    func itemRule(forKey key: String) -> AutomationRule? {
        ItemVisibility.rule(forItemKey: key, in: rules)
    }

    /// A new rule for the item, on, that holds while the Mac is on battery until the user
    /// changes the condition. Not stored until ``saveItemRule(_:)``.
    func newItemRule(forKey key: String, itemName: String) -> AutomationRule {
        AutomationRule(
            name: String(localized: "Show \(itemName) only when…"),
            clauses: [AutomationClause(condition: .power(.battery))],
            action: .showItemOnlyWhile(itemKey: key, hiding: .hidden)
        )
    }

    /// Stores the rule of an item. An item has one rule, so an earlier one for the same item
    /// is replaced.
    func saveItemRule(_ rule: AutomationRule) {
        if let key = ItemVisibility.itemKey(of: rule), let old = itemRule(forKey: key), old.id != rule.id {
            itemRuleMemory.removeValue(forKey: key)
        }
        rules = ItemVisibility.saving(rule, in: rules)
    }

    /// Removes the rule of the item with the given identity key, if it has one. The item stays
    /// where the rule put it.
    func removeItemRule(forKey key: String) {
        if let rule = itemRule(forKey: key) {
            removeRule(withID: rule.id)
        }
    }

    /// The profile without the items that rules control: a profile leaves them where their
    /// rule puts them (item rules win). Keys of earlier versions match through the item
    /// identity; on macOS 27 the applications of the controlled items are left out as well.
    func removingControlledItems(from profile: LayoutProfile) -> LayoutProfile {
        let controlled = controlledItemKeys
        guard !controlled.isEmpty, let appState else {
            return profile
        }
        let itemManager = appState.itemManager
        var result = profile
        result.itemSections = ItemVisibility.removingControlled(from: profile.itemSections) {
            controlled.contains(itemManager.storedIdentityKey($0))
        }
        let layoutKeys = layoutKeys(forItemKeys: controlled)
        result.applicationSections = ItemVisibility.removingControlled(from: profile.applicationSections) {
            layoutKeys.contains($0)
        }
        return result
    }

    /// The macOS 27 layout keys of the items with the given identity keys, which are the
    /// applications of the items. holzBar's own bundle never becomes a key: it would conceal
    /// holzBar's own icon and dividers.
    private func layoutKeys(forItemKeys keys: Set<String>) -> Set<String> {
        guard let appState else {
            return []
        }
        let itemManager = appState.itemManager
        let items = Dictionary(
            itemManager.itemCache.managedItems.map { (itemManager.identityKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return Set(keys.compactMap { key in
            OwnBundle.layoutKey(
                forItemKey: key,
                itemLayoutKey: items[key]?.layoutKey27,
                bundleIdentifier: Constants.bundleIdentifier
            )
        })
    }
}
