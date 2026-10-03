//
//  RevealRules.swift
//  holzBar
//

import Observation
import Foundation
import IOKit.ps
import Network
import OSLog

/// Posted on the main thread whenever IOKit reports a change of a power source
/// (its charge, or whether it is plugged in).
///
/// IOKit's callback is a C function that cannot capture the rules, so it posts this
/// notification instead.
nonisolated private let powerSourcesDidChange = Notification.Name("PowerSourcesDidChange")

/// IOKit's power-source callback. It runs on the run loop its source was added to.
nonisolated private func postPowerSourcesDidChange(_ context: UnsafeMutableRawPointer?) {
    NotificationCenter.default.post(name: powerSourcesDidChange, object: nil)
}

/// Shows the hidden section by itself when something needs attention
/// (jordanbaird/Ice#62): the battery runs low, or the Mac goes offline.
///
/// The section is shown for the "temporarily shown item" interval, then hidden
/// again. Each rule fires once when its condition starts, not again while it
/// lasts (``RevealTrigger``). Both rules react to system events, power-source
/// notifications and ``NWPathMonitor``, so nothing polls, and each one observes its
/// events only while it is turned on.
@MainActor
@Observable
final class RevealRules {
    /// Shows hidden items when the battery falls below ``lowBatteryThreshold``.
    var revealsOnLowBattery = false {
        didSet {
            save()
            updatePowerMonitor()
            batteryRuleChanged()
        }
    }

    /// The battery level, in percent, below which hidden items are shown.
    var lowBatteryThreshold = 20 {
        didSet {
            save()
            batteryRuleChanged()
        }
    }

    /// Shows hidden items when the network connection is lost.
    var revealsWhenOffline = false {
        didSet {
            save()
            updateNetworkMonitor()
        }
    }

    @ObservationIgnored private let logger = Logger(category: "RevealRules")
    @ObservationIgnored private weak var appState: AppState?

    /// The task that follows power-source notifications.
    @ObservationIgnored private var powerSourceTask: Task<Void, Never>?

    /// Watches whether a network path is available.
    ///
    /// `NWPathMonitor` only observes the status of the Mac's network paths; it never
    /// opens a connection or sends anything. It exists only while the offline rule is
    /// on; a cancelled monitor cannot be restarted, so each start creates a new one.
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    /// Whether the next path update only records the current state: a rule turned on
    /// while the Mac is already offline does not fire until the next time it goes offline.
    @ObservationIgnored private var isNetworkBaselinePending = false

    /// The run loop source of IOKit's power-source notifications, which exists only
    /// while the low-battery rule is on.
    @ObservationIgnored private var powerSource: CFRunLoopSource?

    @ObservationIgnored private var batteryTrigger = RevealTrigger()
    @ObservationIgnored private var networkTrigger = RevealTrigger()
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var isSetUp = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        load()

        powerSourceTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: powerSourcesDidChange) {
                self?.checkBattery()
            }
        }

        isSetUp = true
        updatePowerMonitor()
        checkBattery()
        // At launch an offline Mac fires the offline rule, as before.
        updateNetworkMonitor(isLaunch: true)
    }

    // MARK: Monitors

    /// Starts or stops the power-source notifications for the low-battery rule.
    private func updatePowerMonitor() {
        guard isSetUp else {
            return
        }
        if revealsOnLowBattery {
            startPowerMonitor()
        } else {
            stopPowerMonitor()
        }
    }

    /// Starts or stops the network path monitor for the offline rule.
    private func updateNetworkMonitor(isLaunch: Bool = false) {
        guard isSetUp else {
            return
        }
        if revealsWhenOffline {
            startNetworkMonitor(recordsBaseline: !isLaunch)
        } else {
            stopNetworkMonitor()
        }
    }

    private func startPowerMonitor() {
        guard powerSource == nil else {
            return
        }
        // IOKit calls this whenever a power source changes; the source runs on the
        // main run loop, so the notification is posted on the main thread.
        if let source = IOPSNotificationCreateRunLoopSource(postPowerSourcesDidChange, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        } else {
            logger.error("Could not observe power source changes")
        }
    }

    private func stopPowerMonitor() {
        guard let source = powerSource else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = nil
    }

    private func startNetworkMonitor(recordsBaseline: Bool) {
        guard pathMonitor == nil else {
            return
        }
        isNetworkBaselinePending = recordsBaseline
        networkTrigger = RevealTrigger()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor in
                self?.networkChanged(isOffline: isOffline)
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
    }

    private func stopNetworkMonitor() {
        guard let monitor = pathMonitor else {
            return
        }
        monitor.cancel()
        pathMonitor = nil
    }

    private func load() {
        isLoading = true
        defer {
            isLoading = false
        }
        guard let stored = Defaults.dictionary(forKey: .revealRules) else {
            return
        }
        revealsOnLowBattery = stored["LowBattery"] as? Bool ?? revealsOnLowBattery
        lowBatteryThreshold = stored["LowBatteryThreshold"] as? Int ?? lowBatteryThreshold
        revealsWhenOffline = stored["Offline"] as? Bool ?? revealsWhenOffline
    }

    /// Checks the battery at once when the rule is turned on or off or its threshold
    /// changes, instead of waiting for the next power-source change.
    private func batteryRuleChanged() {
        guard isSetUp, !isLoading else {
            return
        }
        checkBattery()
    }

    private func save() {
        guard !isLoading else {
            return
        }
        Defaults.set(
            [
                "LowBattery": revealsOnLowBattery,
                "LowBatteryThreshold": lowBatteryThreshold,
                "Offline": revealsWhenOffline,
            ] as [String: Any],
            forKey: .revealRules
        )
    }

    // MARK: Conditions

    /// The battery level in percent, or `nil` on a Mac without a battery or
    /// while it charges.
    private static func dischargingBatteryLevel() -> Int? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                let level = RevealTrigger.percent(current: current, maximum: maximum)
            else {
                continue
            }
            return level
        }
        return nil
    }

    private func checkBattery() {
        guard revealsOnLowBattery else {
            batteryTrigger = RevealTrigger()
            return
        }
        // While the Mac charges (or has no battery) the level is unknown, so the
        // condition neither starts nor ends: plugging in and out again while the
        // battery stays low does not show the items again.
        guard let level = Self.dischargingBatteryLevel() else {
            return
        }
        if batteryTrigger.update(level < lowBatteryThreshold) {
            reveal(because: "the battery is low")
        }
    }

    private func networkChanged(isOffline: Bool) {
        // An update of a monitor that was stopped meanwhile is stale.
        guard pathMonitor != nil else {
            return
        }
        if isNetworkBaselinePending {
            isNetworkBaselinePending = false
            _ = networkTrigger.update(isOffline)
            return
        }
        let started = networkTrigger.update(isOffline)
        if started, revealsWhenOffline {
            reveal(because: "the network connection was lost")
        }
    }

    // MARK: Revealing

    private func reveal(because reason: String) {
        guard
            let appState,
            let section = appState.menuBarManager.section(withName: .hidden),
            section.isHidden
        else {
            return
        }
        logger.notice("Showing hidden items because \(reason, privacy: .public)")
        section.show()
        appState.menuBarManager.showOnHoverAllowed = false
        let interval = appState.settings.advanced.tempShowInterval
        Task {
            try? await Task.sleep(for: .seconds(interval))
            if !section.isHidden {
                section.hide()
            }
        }
    }
}
