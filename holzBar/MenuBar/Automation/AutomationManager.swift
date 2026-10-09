//
//  AutomationManager.swift
//  holzBar
//

import AppKit
import IOKit.ps
import Network
import Observation
import OSLog

/// Posted on the main thread when IOKit reports a change of a power source. IOKit's callback
/// is a C function that cannot capture the manager, so it posts this notification instead.
nonisolated private let automationPowerDidChange = Notification.Name("AutomationPowerDidChange")

nonisolated private func postAutomationPowerDidChange(_ context: UnsafeMutableRawPointer?) {
    NotificationCenter.default.post(name: automationPowerDidChange, object: nil)
}

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
            save()
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
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var networkKinds: Set<AutomationNetworkKind>?
    @ObservationIgnored private var timeTask: Task<Void, Never>?
    @ObservationIgnored private var storedWiFiMonitor: WiFiNetworkMonitor?

    /// The reader of the Wi-Fi network name. It exists from the first time it is needed.
    var wifiMonitor: WiFiNetworkMonitor {
        if let storedWiFiMonitor {
            return storedWiFiMonitor
        }
        let monitor = WiFiNetworkMonitor()
        monitor.onChange = { [weak self] in
            self?.evaluate()
        }
        storedWiFiMonitor = monitor
        return monitor
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        load()
        isSetUp = true
        sourcesChanged()
        evaluate()
    }

    // MARK: Storage

    private func load() {
        isLoading = true
        defer {
            isLoading = false
        }
        guard
            let data = Defaults.data(forKey: .automationRules),
            let decoded = try? JSONDecoder().decode([AutomationRule].self, from: data)
        else {
            return
        }
        rules = AutomationRule.validated(decoded)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            Defaults.set(data, forKey: .automationRules)
        }
    }

    // MARK: Observers

    /// Starts the observers the enabled rules need and stops the others.
    private func sourcesChanged() {
        guard isSetUp else {
            return
        }
        let needed = AutomationRule.sources(of: rules)
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
            observe(source, notifications: [(NotificationCenter.default, automationPowerDidChange)])
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
        case .lowPowerMode, .runningApps, .frontmostApp, .displays:
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
                    self?.evaluate()
                }
            }
        }
    }

    private func startPowerSource() {
        guard powerSource == nil else {
            return
        }
        if let source = IOPSNotificationCreateRunLoopSource(postAutomationPowerDidChange, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        } else {
            logger.error("Could not observe power source changes")
        }
    }

    private func stopPowerSource() {
        guard let source = powerSource else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = nil
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
        networkKinds = kinds
        evaluate()
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
        return facts
    }

    /// The power source and the level of the internal battery. A Mac without a battery runs
    /// on its adapter and has no level.
    private static func powerFacts() -> (source: AutomationPowerSource?, percent: Int?) {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return (nil, nil)
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }
            let isOnBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            var percent: Int?
            if let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int {
                percent = RevealTrigger.percent(current: current, maximum: maximum)
            }
            return (isOnBattery ? .battery : .adapter, percent)
        }
        return (.adapter, nil)
    }

    // MARK: Evaluating

    /// Checks the rules against the current facts and carries out what changed.
    private func evaluate() {
        guard isSetUp, let appState else {
            return
        }
        // With no enabled rule and nothing remembered there is nothing to do.
        guard rules.contains(where: \.isEnabled) || !engineState.active.isEmpty else {
            return
        }
        let result = AutomationEngine.evaluate(
            rules: rules,
            facts: currentFacts(),
            context: AutomationEngine.Context(
                currentProfile: appState.profiles.currentProfileName,
                isZenOn: appState.menuBarManager.zenMode.isManual
            ),
            state: engineState
        )
        engineState = result.state
        for effect in result.effects {
            perform(effect, with: appState)
        }
    }

    private func perform(_ effect: AutomationEngine.Effect, with appState: AppState) {
        switch effect {
        case .applyProfile(let name):
            logger.notice("An automation rule applies a profile")
            appState.profiles.apply(named: name)
        case .showSection(let section):
            appState.revealRules.reveal(
                section == .alwaysHidden ? .alwaysHidden : .hidden,
                because: "an automation rule asked for it"
            )
        case .setZen(let isOn):
            logger.notice("An automation rule turns Zen mode \(isOn ? "on" : "off", privacy: .public)")
            appState.menuBarManager.setManualZenMode(isOn)
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

    /// Turns a rule on or off.
    func setRule(withID id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }), rules[index].isEnabled != enabled else {
            return
        }
        rules[index].isEnabled = enabled
    }

    func removeRule(withID id: UUID) {
        rules.removeAll { $0.id == id }
    }
}
