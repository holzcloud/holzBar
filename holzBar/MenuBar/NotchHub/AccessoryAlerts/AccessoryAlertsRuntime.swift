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
/// when either goes off, so nothing of the module exists while it is off. It is a consumer of
/// ``ConnectedDevicesService``, which owns the one ``BluetoothDeviceMonitor`` that follows which
/// paired Bluetooth devices are connected and never connects to, searches for or pairs with one.
/// It asks macOS for the Bluetooth permission once, here in ``init(appState:)``, through that
/// monitor and only while the state is not determined: it is the only place that asks. Each
/// change of the connected devices goes through an ``AccessoryTracker``, whose events become
/// ``LiveActivity`` values that are already finished, so each alert widens the notch for five
/// seconds, with its fixed short word and never the device's name; VoiceOver hears each once.
/// The devices connected when the module starts are the baseline and raise no alert. Device
/// names live in memory only, are dropped in ``shutDown()`` and are never logged.
///
/// The battery half takes the accessory levels from ``ConnectedDevicesService``, the one reader
/// of the agreed battery read, so it never calls that read itself and reads nothing while the
/// setting "Read battery levels" is off. Each change of the service's levels feeds an
/// ``AccessoryLowBatteryGate``, whose ids become low-battery alerts.
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

    /// The paired devices that are connected now, from the devices service. Empty without the
    /// Bluetooth permission.
    var connected: [AccessoryDevice] {
        appState?.connectedDevices.connected ?? []
    }

    /// The state of the Bluetooth permission as of the last report of the devices service.
    var access: BluetoothAccess {
        appState?.connectedDevices.access ?? BluetoothDeviceMonitor.access
    }

    /// The rows of the Accessories tab: the devices service's list, from ``ConnectedDeviceList``.
    var deviceRows: [ConnectedDeviceRow] {
        appState?.connectedDevices.rows ?? []
    }

    /// The accessories that report a battery level, from the devices service. Empty while reading
    /// is off or this macOS lacks the call.
    var batteries: [AccessoryBattery] {
        appState?.connectedDevices.batteries ?? []
    }

    /// The level at or below which a battery counted as low at the last read.
    private(set) var lowLevel = AccessoryAlertOptions.defaultLowBatteryLevel

    private var alerts = [LiveActivity]()

    /// What the connect and disconnect alerts follow: the connected devices and whether holzBar
    /// may use Bluetooth at all.
    private struct DeviceState: Equatable {
        let connected: [AccessoryDevice]
        let isAuthorized: Bool
    }

    /// The consumer names this runtime registers under with the devices service: one for the
    /// module while it runs, one for the Accessories tab while it is on screen.
    private static let devicesConsumer = "accessory-alerts"
    private static let hubDevicesConsumer = "hub-devices"

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var tracker = AccessoryTracker()
    @ObservationIgnored private var devicesLoop: ObservationLoop?
    @ObservationIgnored private var batteriesLoop: ObservationLoop?
    @ObservationIgnored private var lastDevices = [AccessoryDevice]()
    @ObservationIgnored private var lowGate = AccessoryLowBatteryGate()
    @ObservationIgnored private var isRunning = true

    /// Starts following the connected devices through the devices service. The Bluetooth
    /// question is asked here, once, when macOS has not been asked yet; it is the only place that
    /// asks.
    init(appState: AppState) {
        self.appState = appState
        let devices = appState.connectedDevices
        devices.begin(Self.devicesConsumer, wantsDevices: true)
        if BluetoothDeviceMonitor.access == .notDetermined {
            devices.bluetoothMonitor?.requestAuthorization()
        }
        devicesLoop = ObservationLoop.observe(
            { [weak self] in
                self?.deviceState ?? DeviceState(connected: [], isAuthorized: false)
            },
            onChange: { [weak self] state in
                self?.devicesDidChange(state)
            }
        )
        // The baseline: what is connected now is not news.
        devicesDidChange(deviceState)
        // The battery half: every change of the service's levels runs the low-battery gate.
        batteriesLoop = ObservationLoop.observe(
            { [weak self] in
                self?.batteries ?? []
            },
            onChange: { [weak self] _ in
                self?.updateLowBatteryAlerts()
            }
        )
        updateLowBatteryAlerts()
    }

    // MARK: Devices

    private var deviceState: DeviceState {
        DeviceState(
            connected: appState?.connectedDevices.connected ?? [],
            isAuthorized: appState?.connectedDevices.access == .allowed
        )
    }

    /// Takes the connected devices the service reports, and raises an alert for each event.
    private func devicesDidChange(_ state: DeviceState) {
        guard isRunning else {
            return
        }
        guard state.isAuthorized else {
            // Without the permission nothing is known; what is connected once it is allowed is
            // the baseline, not a set of new connections.
            tracker.reset()
            lastDevices = []
            return
        }
        // A device that connects or leaves makes the service read the levels again (its own
        // Bluetooth notification), so nothing more is asked here.
        let devices = state.connected
        if devices != lastDevices {
            lastDevices = devices
        }
        let now = Date.now
        let events = tracker.update(connected: devices, now: now)
        // The tracker sees every snapshot, so a switch turned on later alerts only for new events.
        let options = AccessoryAlertsSettings.options()
        var raised = alerts.filter { now.timeIntervalSince($0.startedAt) < Self.alertRetention }
        for event in events where options.allows(event) {
            let raisedAlert: LiveActivity
            switch event {
            case .connected(let device):
                raisedAlert = alert(
                    for: device,
                    title: String(localized: "\(device.name) connected"),
                    shortWord: String(localized: "Connected"),
                    at: now
                )
            case .disconnected(let device):
                raisedAlert = alert(
                    for: device,
                    title: String(localized: "\(device.name) disconnected"),
                    shortWord: String(localized: "Disconnected"),
                    at: now
                )
            }
            raised.append(raisedAlert)
            announce(raisedAlert)
        }
        if raised != alerts {
            alerts = raised
        }
    }

    /// An alert: an activity that is finished when it is created, so the hub holds it for its
    /// five seconds and drops it. The title names the accessory, for VoiceOver and the list; the
    /// short word is the fixed word the widened notch shows, never the name.
    private func alert(for device: AccessoryDevice, title: String, shortWord: String, at date: Date) -> LiveActivity {
        LiveActivity(
            id: UUID().uuidString,
            moduleID: moduleID,
            kind: .other,
            symbol: device.symbolName,
            title: title,
            priority: 10,
            startedAt: date,
            finishedAt: date,
            tint: .accent,
            announcesItself: true,
            compactValue: shortWord
        )
    }

    /// Tells VoiceOver about an alert, because a state that lasts five seconds is easy to miss
    /// without sight. Nothing is posted while VoiceOver is off. The text names the accessory, which
    /// the widened notch never draws; it stays in the accessibility layer of this Mac and is never
    /// logged.
    private func announce(_ alert: LiveActivity) {
        guard NSWorkspace.shared.isVoiceOverEnabled else {
            return
        }
        let text = [alert.title, alert.detail].compactMap(\.self).joined(separator: ", ")
        AccessibilityNotification.Announcement(text).post()
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

    private var lowestBattery: AccessoryBattery? {
        batteries.min { ($0.percent, $0.name, $0.id) < ($1.percent, $1.name, $1.id) }
    }

    /// Whether the user wants levels but this macOS lacks the call that gives them.
    var batteryReadingUnavailable: Bool {
        appState?.connectedDevices.batteryReadingUnavailable ?? false
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(AccessoryAlertsBodyView(runtime: self))
    }

    /// Reads the permission and the devices again when the hub opens or closes. An unchanged
    /// snapshot raises nothing.
    func hubVisibilityDidChange(isOpen _: Bool) {
        appState?.connectedDevices.refresh()
    }

    /// The Accessories tab came on screen: it needs the devices and their levels for as long as
    /// it shows.
    func devicesListDidAppear() {
        appState?.connectedDevices.begin(Self.hubDevicesConsumer, wantsDevices: true)
        appState?.connectedDevices.refresh()
    }

    /// The Accessories tab went off screen.
    func devicesListDidDisappear() {
        appState?.connectedDevices.end(Self.hubDevicesConsumer)
    }

    /// Runs the low-battery logic again on the current levels after a setting changed (the switch
    /// for reading, for the alert, or the level). It reads nothing: the settings view tells the
    /// devices service when the switch changes, and the service reads then.
    func settingsDidChange() {
        updateLowBatteryAlerts()
    }

    /// Gives the devices service back and stops the observations, and lets go of every device,
    /// battery and alert.
    func shutDown() {
        isRunning = false
        devicesLoop?.cancel()
        devicesLoop = nil
        batteriesLoop?.cancel()
        batteriesLoop = nil
        appState?.connectedDevices.end(Self.devicesConsumer)
        appState?.connectedDevices.end(Self.hubDevicesConsumer)
        lastDevices = []
        alerts = []
        tracker.reset()
        lowGate.reset()
    }

    // MARK: Batteries

    /// Runs the low-battery gate on the devices service's levels: reads the options, updates
    /// ``lowLevel`` and raises an alert for each battery that fell to the low level.
    ///
    /// While "Read battery levels" is off there are no levels and the gate forgets what it
    /// announced; a low battery that is already low when the alert is turned on, or reading is
    /// turned on again, counts as a first reading.
    private func updateLowBatteryAlerts() {
        guard isRunning else {
            return
        }
        let options = AccessoryAlertsSettings.options()
        if lowLevel != options.lowBatteryLevel {
            lowLevel = options.lowBatteryLevel
        }
        guard AccessoryAlertsSettings.readsBattery(), options.allowsLowBattery else {
            lowGate.reset()
            return
        }
        let read = batteries
        let levels = Dictionary(read.map { ($0.id, $0.percent) }, uniquingKeysWith: { first, _ in first })
        let lowIDs = lowGate.update(levels: levels, threshold: options.lowBatteryLevel)
        raiseLowBatteryAlerts(for: read.filter { lowIDs.contains($0.id) }, at: .now)
    }

    private func raiseLowBatteryAlerts(for lowBatteries: [AccessoryBattery], at now: Date) {
        var raised = alerts.filter { now.timeIntervalSince($0.startedAt) < Self.alertRetention }
        for battery in lowBatteries {
            let isCritical = battery.percent <= 10
            let lowAlert = LiveActivity(
                id: UUID().uuidString,
                moduleID: moduleID,
                kind: .other,
                symbol: isCritical ? "battery.0percent" : "battery.25percent",
                title: String(localized: "\(battery.name) battery low"),
                detail: battery.percentText,
                priority: 30,
                startedAt: now,
                finishedAt: now,
                tint: isCritical ? .red : .amber,
                announcesItself: true,
                compactValue: battery.percentText
            )
            raised.append(lowAlert)
            announce(lowAlert)
        }
        if raised != alerts {
            alerts = raised
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
