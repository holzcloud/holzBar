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

    private var alerts = [LiveActivity]()

    @ObservationIgnored private var tracker = AccessoryTracker()
    @ObservationIgnored private let monitor = BluetoothDeviceMonitor()
    @ObservationIgnored private var activationTask: Task<Void, Never>?

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
            }
            return
        }
        let devices = monitor.connectedDevices()
        if devices != connected {
            connected = devices
        }
        let now = Date.now
        let events = tracker.update(connected: devices, now: now)
        var raised = alerts.filter { now.timeIntervalSince($0.startedAt) < Self.alertRetention }
        for event in events {
            if case .connected(let device) = event {
                raised.append(alert(for: device, title: String(localized: "\(device.name) connected"), at: now))
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

    /// The Overview card: how many accessories are connected, and the first two names.
    var tile: HubTile? {
        HubTile(
            symbol: "airpods",
            title: Text("Accessories"),
            value: String(connected.count),
            unit: Text("connected"),
            detail: connected.isEmpty ? nil : Text(verbatim: connected.prefix(2).map(\.name).joined(separator: ", "))
        )
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(AccessoryAlertsBodyView(runtime: self))
    }

    /// Reads the permission and the devices again when the hub opens or closes. An unchanged
    /// snapshot raises nothing.
    func hubVisibilityDidChange(isOpen: Bool) {
        monitor.refreshAuthorization()
        devicesDidChange()
    }

    /// Stops the monitor and lets go of every device and alert.
    func shutDown() {
        activationTask?.cancel()
        activationTask = nil
        monitor.onChange = nil
        monitor.stop()
        connected = []
        alerts = []
        tracker.reset()
    }
}
