//
//  ConnectedDevicesService.swift
//  holzBar
//

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
/// leave memory with the last consumer. This type never asks for the Bluetooth permission.
@MainActor
@Observable
final class ConnectedDevicesService {
    /// The rows of the list, from ``ConnectedDeviceList``. Empty while no consumer exists.
    private(set) var rows = [ConnectedDeviceRow]()

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

    /// The consumers that are registered, each with whether it wants the Bluetooth devices.
    @ObservationIgnored private var consumers = [String: Bool]()
    @ObservationIgnored private var lastRead = Date.now
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readAgain = false
    /// Counts the times the last consumer left, so a read that outlived its consumers does not
    /// touch the state of the next ones.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var powerTask: Task<Void, Never>?
    @ObservationIgnored private var beganPowerEvents = false

    /// Loads the switch of the battery read. Nothing runs until a consumer registers.
    func performSetup(with _: AppState) {
        readsBattery = AccessoryAlertsSettings.readsBattery()
    }

    // MARK: Consumers

    /// Registers a surface that shows the list. The first consumer starts the power-source events
    /// and the first read; registering the same name again only updates what it wants.
    func begin(_ consumer: String, wantsDevices: Bool) {
        let wasIdle = consumers.isEmpty
        consumers[consumer] = wantsDevices
        guard wasIdle else {
            return
        }
        readsBattery = AccessoryAlertsSettings.readsBattery()
        access = BluetoothDeviceMonitor.access
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
        guard consumers.removeValue(forKey: consumer) != nil, consumers.isEmpty else {
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

    /// Reads again soon, for a surface that opened or an event that may have changed a level.
    func refresh() {
        scheduleRead()
    }

    /// Takes the "Read battery levels" switch again and reads again. A consumer calls it after
    /// the switch changed.
    func batterySwitchDidChange() {
        readsBattery = AccessoryAlertsSettings.readsBattery()
        scheduleRead()
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
            : ConnectedDeviceList.rows(connected: [], disconnected: [], batteries: batteries)
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
