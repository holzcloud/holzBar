//
//  BluetoothDeviceMonitor.swift
//  holzBar
//

import CoreBluetooth
import IOBluetooth
import Observation

/// Whether macOS lets holzBar use Bluetooth, in the three states the interface needs.
nonisolated enum BluetoothAccess: Sendable {
    /// The user allowed it.
    case allowed
    /// macOS has not asked yet.
    case notDetermined
    /// The user refused it, or a profile or the system restricts it.
    case denied
}

/// Follows which of the paired Bluetooth devices are connected, for the accessory alerts.
///
/// It registers for the system's connect and disconnect notifications; nothing polls. It reads
/// which paired devices are connected, nothing else: it never opens a connection to a device,
/// never searches for devices, never pairs and never sends. Every call into IOBluetooth is made
/// only while ``isAuthorized`` is true, and the Bluetooth question is asked by
/// ``requestAuthorization()`` alone, which the owner calls when it starts. Device names and
/// addresses stay in memory and out of the logs.
@MainActor
@Observable
final class BluetoothDeviceMonitor: NSObject, CBCentralManagerDelegate {
    /// The state of the Bluetooth permission, read without asking anything.
    nonisolated static var access: BluetoothAccess {
        switch CBManager.authorization {
        case .allowedAlways: .allowed
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// The state of the Bluetooth permission as of the last ``refreshAuthorization()``.
    private(set) var authorization = CBManager.authorization

    /// Called after a device connected or disconnected, or the permission changed.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications = [String: IOBluetoothUserNotification]()
    @ObservationIgnored private var centralManager: CBCentralManager?

    /// Whether holzBar may use Bluetooth.
    var isAuthorized: Bool {
        authorization == .allowedAlways
    }

    /// Reads the permission again, and starts or ends the notifications when it changed while
    /// monitoring.
    func refreshAuthorization() {
        let current = CBManager.authorization
        guard current != authorization else {
            return
        }
        authorization = current
        if isMonitoring {
            if isAuthorized {
                registerNotifications()
            } else {
                unregisterNotifications()
            }
        }
        onChange?()
    }

    /// Starts following the connected devices. Without the permission nothing is registered;
    /// the notifications follow once the user allows it.
    func start() {
        guard !isMonitoring else {
            return
        }
        isMonitoring = true
        refreshAuthorization()
        if isAuthorized {
            registerNotifications()
        }
    }

    /// Stops following them and lets go of everything the monitor holds.
    func stop() {
        isMonitoring = false
        unregisterNotifications()
        centralManager?.delegate = nil
        centralManager = nil
    }

    /// Asks macOS for the Bluetooth permission, once, when the user has not answered yet. The
    /// system shows its own question. The manager made for it never scans or connects, and its
    /// "turn on Bluetooth" alert is off.
    func requestAuthorization() {
        guard CBManager.authorization == .notDetermined, centralManager == nil else {
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// The paired devices that are connected now, by name. Empty without the permission.
    func connectedDevices() -> [AccessoryDevice] {
        guard isAuthorized else {
            return []
        }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var result = [AccessoryDevice]()
        for device in paired where device.isConnected() {
            guard let accessory = AccessoryDevice(
                address: device.addressString ?? "",
                name: device.name ?? "",
                majorClass: Int(device.deviceClassMajor),
                minorClass: Int(device.deviceClassMinor)
            ) else {
                continue
            }
            result.append(accessory)
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Notifications

    private func registerNotifications() {
        guard isAuthorized, connectNotification == nil else {
            return
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired where device.isConnected() {
            watchDisconnect(of: device)
        }
    }

    private func unregisterNotifications() {
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
    }

    private func watchDisconnect(of device: IOBluetoothDevice) {
        guard isAuthorized, let address = device.addressString, disconnectNotifications[address] == nil else {
            return
        }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watchDisconnect(of: device)
        onChange?()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotifications = disconnectNotifications.filter { $0.value !== notification }
        onChange?()
    }

    // MARK: Delegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.permissionWasAnswered()
        }
    }

    /// Lets go of the manager that asked, once the user has answered, and reads the permission.
    private func permissionWasAnswered() {
        if CBManager.authorization != .notDetermined {
            centralManager?.delegate = nil
            centralManager = nil
        }
        refreshAuthorization()
    }
}
