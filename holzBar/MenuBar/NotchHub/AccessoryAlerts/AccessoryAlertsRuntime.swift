//
//  AccessoryAlertsRuntime.swift
//  holzBar
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// The running part of the Accessory alerts module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It owns one
/// ``BluetoothDeviceMonitor``, which follows which paired Bluetooth devices are connected and
/// never connects to, searches for or pairs with one. It asks macOS for the Bluetooth permission
/// once, here in ``init(appState:)`` and only while the state is not determined. Each report of
/// the monitor goes through an ``AccessoryTracker``, whose events become ``LiveActivity`` values
/// that are already finished, so the hub shows each as a capsule below the notch for five
/// seconds. The devices connected when the module starts are the baseline and raise no alert.
/// Device names live in memory only, are dropped in ``shutDown()`` and are never logged.
///
/// The battery half reads accessory levels through ``AccessoryBatterySource``, only while the
/// setting "Read battery levels" is on. A read follows events: the power-source notification, a
/// device connecting or leaving, and the hub opening. One coarse wait of five minutes covers the
/// level changing silently; it is armed only while an accessory with a level is connected. Each
/// read feeds an ``AccessoryLowBatteryGate``, whose ids become low-battery alerts.
@MainActor
@Observable
final class AccessoryAlertsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "accessory-alerts"

    /// How long a raised alert is kept before the next report drops it. The hub shows it for
    /// ``HubActivityBoard/finishedHold`` seconds only.
    private static let alertRetention: TimeInterval = 10

    let moduleID = AccessoryAlertsRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// The paired devices that are connected now. Empty without the Bluetooth permission.
    private(set) var connected = [AccessoryDevice]()

    /// The state of the Bluetooth permission as of the last report.
    private(set) var access = BluetoothDeviceMonitor.access

    /// The accessories that report a battery level, from the last read. Empty while reading is
    /// off or this macOS lacks the call.
    private(set) var batteries = [AccessoryBattery]()

    /// The level at or below which a battery counted as low at the last read.
    private(set) var lowLevel = AccessoryAlertOptions.defaultLowBatteryLevel

    private var alerts = [LiveActivity]()

    @ObservationIgnored private var tracker = AccessoryTracker()
    @ObservationIgnored private let monitor = BluetoothDeviceMonitor()
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var lowGate = AccessoryLowBatteryGate()
    @ObservationIgnored private var isRunning = true
    @ObservationIgnored private var lastRead = Date.now
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readAgain = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var powerTask: Task<Void, Never>?
    @ObservationIgnored private var beganPowerEvents = false

    /// Starts following the connected devices. The Bluetooth question is asked here, once, when
    /// macOS has not been asked yet.
    init(appState _: AppState) {
        monitor.onChange = { [weak self] in
            self?.devicesDidChange()
        }
        monitor.refreshAuthorization()
        if BluetoothDeviceMonitor.access == .notDetermined {
            monitor.requestAuthorization()
        }
        monitor.start()
        // The baseline: what is connected now is not news.
        devicesDidChange()
        // A change made in System Settings shows without a restart.
        activationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.monitor.refreshAuthorization()
            }
        }
        // The battery half: a power-source change may be an accessory's.
        PowerSourceEvents.shared.begin()
        beganPowerEvents = true
        powerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .powerSourcesDidChange) {
                self?.scheduleBatteryRefresh()
            }
        }
        scheduleBatteryRefresh()
    }

    // MARK: Devices

    /// Reads the connected devices, shows them, and raises an alert for each event.
    private func devicesDidChange() {
        if access != BluetoothDeviceMonitor.access {
            access = BluetoothDeviceMonitor.access
        }
        guard monitor.isAuthorized else {
            // Without the permission nothing is known; what is connected once it is allowed is
            // the baseline, not a set of new connections.
            tracker.reset()
            if !connected.isEmpty {
                connected = []
                scheduleBatteryRefresh()
            }
            return
        }
        let devices = monitor.connectedDevices()
        if devices != connected {
            connected = devices
            scheduleBatteryRefresh()
        }
        let now = Date.now
        let events = tracker.update(connected: devices, now: now)
        // The tracker sees every snapshot, so a switch turned on later alerts only for new events.
        let options = AccessoryAlertsSettings.options()
        var raised = alerts.filter { now.timeIntervalSince($0.startedAt) < Self.alertRetention }
        for event in events where options.allows(event) {
            switch event {
            case .connected(let device):
                raised.append(alert(for: device, title: String(localized: "\(device.name) connected"), at: now))
            case .disconnected(let device):
                raised.append(alert(for: device, title: String(localized: "\(device.name) disconnected"), at: now))
            }
        }
        if raised != alerts {
            alerts = raised
        }
    }

    /// An alert: an activity that is finished when it is created, so the hub holds it for its
    /// five seconds and drops it.
    private func alert(for device: AccessoryDevice, title: String, at date: Date) -> LiveActivity {
        LiveActivity(
            id: UUID().uuidString,
            moduleID: moduleID,
            kind: .other,
            symbol: device.symbolName,
            title: title,
            priority: 10,
            startedAt: date,
            finishedAt: date,
            tint: .accent
        )
    }

    // MARK: Hub

    var activities: [LiveActivity] {
        alerts
    }

    /// The Overview card: how many accessories are connected, and the first two names, or the
    /// lowest battery when levels are known.
    var tile: HubTile? {
        HubTile(
            symbol: "airpods",
            title: Text("Accessories"),
            value: String(connected.count),
            unit: Text("connected"),
            detail: tileDetail
        )
    }

    private var tileDetail: Text? {
        if let lowest = lowestBattery {
            return Text(verbatim: "\(lowest.name) \(lowest.percentText)")
        }
        return connected.isEmpty ? nil : Text(verbatim: connected.prefix(2).map(\.name).joined(separator: ", "))
    }

    /// The lowest battery is shown while it is at or below the low-battery level.
    var statusPill: HubStatusPill? {
        guard let lowest = lowestBattery, lowest.percent <= lowLevel else {
            return nil
        }
        return HubStatusPill(
            symbol: "battery.25percent",
            text: lowest.percentText,
            accessibilityLabel: Text("\(lowest.name), battery \(lowest.percent) percent")
        )
    }

    private var lowestBattery: AccessoryBattery? {
        batteries.min { ($0.percent, $0.name, $0.id) < ($1.percent, $1.name, $1.id) }
    }

    /// Whether the user wants levels but this macOS lacks the call that gives them.
    var batteryReadingUnavailable: Bool {
        AccessoryAlertsSettings.readsBattery() && !AccessoryBatterySource.isAvailable
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(AccessoryAlertsBodyView(runtime: self))
    }

    /// Reads the permission and the devices again when the hub opens or closes. An unchanged
    /// snapshot raises nothing.
    func hubVisibilityDidChange(isOpen: Bool) {
        monitor.refreshAuthorization()
        devicesDidChange()
        if isOpen {
            scheduleBatteryRefresh()
        }
    }

    /// Reads the batteries again after a setting changed: the switch for reading, for the
    /// alert, or the level.
    func settingsDidChange() {
        scheduleBatteryRefresh()
    }

    /// Stops the monitor, the notification, the tasks and the wait, and lets go of every device,
    /// battery and alert.
    func shutDown() {
        isRunning = false
        activationTask?.cancel()
        activationTask = nil
        powerTask?.cancel()
        powerTask = nil
        readTask?.cancel()
        readTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        if beganPowerEvents {
            PowerSourceEvents.shared.end()
            beganPowerEvents = false
        }
        monitor.onChange = nil
        monitor.stop()
        connected = []
        batteries = []
        alerts = []
        tracker.reset()
        lowGate.reset()
    }

    // MARK: Batteries

    /// Reads the batteries soon. Reads never overlap: a request that arrives during one asks for
    /// one more after it.
    private func scheduleBatteryRefresh() {
        guard isRunning else {
            return
        }
        guard readTask == nil else {
            readAgain = true
            return
        }
        readTask = Task { [weak self] in
            await self?.readUntilQuiet()
        }
    }

    private func readUntilQuiet() async {
        repeat {
            readAgain = false
            await refreshBatteries()
        } while readAgain && isRunning && !Task.isCancelled
        readTask = nil
    }

    /// Reads the accessory batteries once, shows them, raises an alert for each that fell to the
    /// low level and arms the coarse wait.
    ///
    /// The undocumented call is made only while the setting "Read battery levels" is on and this
    /// macOS has it; otherwise the list is empty and nothing is read.
    func refreshBatteries() async {
        guard AccessoryAlertsSettings.readsBattery(), AccessoryBatterySource.isAvailable else {
            clearBatteries()
            return
        }
        let read = await AccessoryBatterySource.read()
        // The module or the setting may have gone off while the read ran.
        guard isRunning, AccessoryAlertsSettings.readsBattery() else {
            clearBatteries()
            return
        }
        let now = Date.now
        lastRead = now
        if read != batteries {
            batteries = read
        }
        let options = AccessoryAlertsSettings.options()
        if lowLevel != options.lowBatteryLevel {
            lowLevel = options.lowBatteryLevel
        }
        if options.allowsLowBattery {
            let levels = Dictionary(read.map { ($0.id, $0.percent) }, uniquingKeysWith: { first, _ in first })
            let lowIDs = lowGate.update(levels: levels, threshold: options.lowBatteryLevel)
            raiseLowBatteryAlerts(for: read.filter { lowIDs.contains($0.id) }, at: now)
        } else {
            // Turned on later, a battery that is already low counts as a first reading.
            lowGate.reset()
        }
        armBatteryWait()
    }

    private func clearBatteries() {
        refreshTask?.cancel()
        refreshTask = nil
        lowGate.reset()
        if !batteries.isEmpty {
            batteries = []
        }
    }

    private func raiseLowBatteryAlerts(for lowBatteries: [AccessoryBattery], at now: Date) {
        var raised = alerts.filter { now.timeIntervalSince($0.startedAt) < Self.alertRetention }
        for battery in lowBatteries {
            let isCritical = battery.percent <= 10
            raised.append(
                LiveActivity(
                    id: UUID().uuidString,
                    moduleID: moduleID,
                    kind: .other,
                    symbol: isCritical ? "battery.0percent" : "battery.25percent",
                    title: String(localized: "\(battery.name) battery low"),
                    detail: battery.percentText,
                    priority: 30,
                    startedAt: now,
                    finishedAt: now,
                    tint: isCritical ? .red : .amber
                )
            )
        }
        if raised != alerts {
            alerts = raised
        }
    }

    /// Arms the one coarse wait, only while an accessory with a level is connected. It replaces
    /// the previous one, and a read re-arms it.
    private func armBatteryWait() {
        refreshTask?.cancel()
        refreshTask = nil
        guard
            isRunning,
            let next = AccessoryRefreshPolicy.next(hasBatteryAccessory: !batteries.isEmpty, lastRead: lastRead)
        else {
            return
        }
        refreshTask = Task { [weak self] in
            let delay = max(next.timeIntervalSinceNow, 1)
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(60), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.scheduleBatteryRefresh()
        }
    }
}

extension AccessoryBattery {
    /// The level as a whole percentage in the user's format, such as "20%".
    var percentText: String {
        Self.percentText(percent)
    }

    /// A whole percentage in the user's format.
    static func percentText(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
