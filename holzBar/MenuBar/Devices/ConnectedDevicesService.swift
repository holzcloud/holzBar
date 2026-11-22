//
//  ConnectedDevicesService.swift
//  holzBar
//

import AppKit
import Foundation
import Observation

/// The one reader of the connected devices and their levels, for the Devices list in Settings,
/// the hub's Accessories tab and, later, the Lowest Device Battery widget.
///
/// Surfaces register as consumers while they show something (``begin(_:wantsDevices:)`` and
/// ``end(_:)``). With no consumer nothing exists here: no read, no task, no wait and no use of
/// the shared power-source run loop source, and the rows are gone from memory. While one is
/// registered a power-source change schedules a read, reads never overlap (one runs, at most one
/// more is asked for), and after a read one coarse wait of ``AccessoryRefreshPolicy`` covers a
/// level that changes silently, armed only while a level exists.
///
/// Levels come from ``AccessoryBatterySource/read()``, the one agreed private call, and only
/// while "Read battery levels" is on and the call exists; otherwise the batteries are empty and
/// nothing is called. Names and levels stay in memory, are never stored, exported or logged, and
/// leave memory with the last consumer.
///
/// This is the one Bluetooth path of the device lists and the accessory alerts: while a consumer
/// wants devices it owns the one ``BluetoothDeviceMonitor`` (the system's connect and disconnect
/// notifications and the list of paired devices), and nothing else in holzBar's device surfaces
/// creates one. It never asks for the Bluetooth permission: without the permission the monitor
/// registers nothing and calls nothing in IOBluetooth, and the lists show the batteries only.
/// The one question is asked by the Accessory alerts module of the hub, through ``bluetoothMonitor``.
@MainActor
@Observable
final class ConnectedDevicesService {
    /// The rows of the list, from ``ConnectedDeviceList``. Empty while no consumer exists.
    private(set) var rows = [ConnectedDeviceRow]()

    /// The paired devices that are connected now, from the last snapshot of the monitor. Empty
    /// without the Bluetooth permission and while no consumer wants devices.
    private(set) var connected = [AccessoryDevice]()

    /// The accessories that report a level, from the last read. Empty while reading is off, this
    /// macOS lacks the call or no consumer exists.
    private(set) var batteries = [AccessoryBattery]()

    /// What macOS lets holzBar do with Bluetooth, read without asking anything.
    private(set) var access = BluetoothDeviceMonitor.access

    /// Whether "Read battery levels" is on, as of the last ``batterySwitchDidChange()``.
    private(set) var readsBattery = AccessoryAlertsSettings.readsBattery()

    /// Whether the user wants levels but this macOS lacks the call that gives them.
    var batteryReadingUnavailable: Bool {
        readsBattery && !AccessoryBatterySource.isAvailable
    }

    /// The one Bluetooth monitor, while a consumer wants devices; lent to the Accessory alerts
    /// module for its one permission question. `nil` while none does.
    var bluetoothMonitor: BluetoothDeviceMonitor? {
        monitor
    }

    /// The consumers that are registered, each with whether it wants the Bluetooth devices.
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var consumers = [String: Bool]()
    @ObservationIgnored private var monitor: BluetoothDeviceMonitor?
    /// The paired devices that are not connected, for the grey rows.
    @ObservationIgnored private var disconnected = [AccessoryDevice]()
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var lastRead = Date.now
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readAgain = false
    /// Counts the times the last consumer left, so a read that outlived its consumers does not
    /// touch the state of the next ones.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var powerTask: Task<Void, Never>?
    @ObservationIgnored private var beganPowerEvents = false

    /// Loads the switch of the battery read and keeps the app state, which holds the shared monitor
    /// that the switch must tell. Nothing runs until a consumer registers.
    func performSetup(with appState: AppState) {
        self.appState = appState
        readsBattery = AccessoryAlertsSettings.readsBattery()
    }

    // MARK: Consumers

    /// Registers a surface that shows the list. The first consumer starts the power-source events
    /// and the first read; registering the same name again only updates what it wants.
    func begin(_ consumer: String, wantsDevices: Bool) {
        let wasIdle = consumers.isEmpty
        consumers[consumer] = wantsDevices
        if access != BluetoothDeviceMonitor.access {
            access = BluetoothDeviceMonitor.access
        }
        updateMonitor()
        guard wasIdle else {
            return
        }
        readsBattery = AccessoryAlertsSettings.readsBattery()
        PowerSourceEvents.shared.begin()
        beganPowerEvents = true
        powerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .powerSourcesDidChange) {
                self?.scheduleRead()
            }
        }
        scheduleRead()
    }

    /// Gives a surface back. The last one to leave ends the task, the wait and the power-source
    /// use and empties the rows and the batteries, so no name stays in memory.
    func end(_ consumer: String) {
        guard consumers.removeValue(forKey: consumer) != nil else {
            return
        }
        updateMonitor()
        guard consumers.isEmpty else {
            return
        }
        powerTask?.cancel()
        powerTask = nil
        readTask?.cancel()
        readTask = nil
        waitTask?.cancel()
        waitTask = nil
        readAgain = false
        generation += 1
        if beganPowerEvents {
            PowerSourceEvents.shared.end()
            beganPowerEvents = false
        }
        batteries = []
        rows = []
    }

    /// Reads the permission, the devices and the levels again, for a surface that opened.
    func refresh() {
        monitor?.refreshAuthorization()
        takeSnapshot()
        scheduleRead()
    }

    /// Takes the "Read battery levels" switch again and reads again, and tells the shared monitor,
    /// whose device battery reading follows the same switch. A consumer calls it after the switch
    /// changed.
    func batterySwitchDidChange() {
        readsBattery = AccessoryAlertsSettings.readsBattery()
        scheduleRead()
        appState?.systemMonitor.deviceBatterySwitchDidChange()
    }

    // MARK: Bluetooth

    /// Creates and starts the one monitor when a consumer wants devices and stops and drops it
    /// when none does. Starting it asks nothing: the monitor registers its notifications only
    /// while macOS already allows Bluetooth.
    private func updateMonitor() {
        let wantsDevices = consumers.values.contains(true)
        if wantsDevices, monitor == nil {
            let created = BluetoothDeviceMonitor()
            created.onChange = { [weak self] in
                self?.bluetoothDidChange()
            }
            monitor = created
            created.start()
            // A change made in System Settings shows without a restart.
            activationTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                    self?.monitor?.refreshAuthorization()
                }
            }
            takeSnapshot()
        } else if !wantsDevices, let existing = monitor {
            activationTask?.cancel()
            activationTask = nil
            existing.onChange = nil
            existing.stop()
            monitor = nil
            access = BluetoothDeviceMonitor.access
            if !connected.isEmpty {
                connected = []
            }
            disconnected = []
            rebuildRows()
        }
    }

    /// A device connected or left, or the permission changed: take a new snapshot and read the
    /// levels again.
    private func bluetoothDidChange() {
        takeSnapshot()
        scheduleRead()
    }

    /// Reads the paired devices from the monitor (empty without the permission), publishes the
    /// connected ones and rebuilds the rows.
    private func takeSnapshot() {
        guard let monitor else {
            return
        }
        if access != BluetoothDeviceMonitor.access {
            access = BluetoothDeviceMonitor.access
        }
        let snapshot = monitor.pairedDevices()
        if snapshot.connected != connected {
            connected = snapshot.connected
        }
        disconnected = snapshot.disconnected
        rebuildRows()
    }

    // MARK: Reading

    /// Reads soon. Reads never overlap: a request that arrives during one asks for one more
    /// after it. Nothing is read without a consumer.
    private func scheduleRead() {
        guard !consumers.isEmpty else {
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
        let mine = generation
        repeat {
            readAgain = false
            await readBatteries(generation: mine)
        } while readAgain && !consumers.isEmpty && !Task.isCancelled && mine == generation
        if mine == generation {
            readTask = nil
        }
    }

    /// Reads the batteries once, rebuilds the rows and arms the coarse wait. The undocumented
    /// call is made only while the switch is on and this macOS has it.
    private func readBatteries(generation mine: Int) async {
        guard readsBattery, AccessoryBatterySource.isAvailable else {
            clearBatteries()
            return
        }
        let read = await AccessoryBatterySource.read()
        // The last consumer or the switch may have gone while the read ran.
        guard mine == generation, !consumers.isEmpty, readsBattery else {
            if mine == generation {
                clearBatteries()
            }
            return
        }
        lastRead = .now
        if read != batteries {
            batteries = read
        }
        rebuildRows()
        armWait()
    }

    private func clearBatteries() {
        waitTask?.cancel()
        waitTask = nil
        if !batteries.isEmpty {
            batteries = []
        }
        rebuildRows()
    }

    private func rebuildRows() {
        let rebuilt = consumers.isEmpty
            ? []
            : ConnectedDeviceList.rows(connected: connected, disconnected: disconnected, batteries: batteries)
        if rebuilt != rows {
            rows = rebuilt
        }
    }

    /// Arms the one coarse wait, only while a level exists. It replaces the previous one, and a
    /// read re-arms it.
    private func armWait() {
        waitTask?.cancel()
        waitTask = nil
        guard let next = AccessoryRefreshPolicy.next(hasBatteryAccessory: !batteries.isEmpty, lastRead: lastRead) else {
            return
        }
        waitTask = Task { [weak self] in
            let delay = max(next.timeIntervalSinceNow, 1)
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(60), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.scheduleRead()
        }
    }
}
