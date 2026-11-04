//
//  AutomationBluetoothObserver.swift
//  holzBar
//

import Foundation
import IOBluetooth

/// Follows which paired Bluetooth devices are connected, for the automation condition "a
/// Bluetooth device is connected".
///
/// It registers for the system's connect and disconnect notifications; nothing polls. It is the
/// only part of holzBar that makes macOS ask for the Bluetooth permission, and it exists only
/// while an enabled rule has the condition. Device names stay on the Mac and out of the logs.
@MainActor
final class AutomationBluetoothObserver: NSObject {
    /// Called after a device connected or disconnected.
    var onChange: (() -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications = [IOBluetoothUserNotification]()

    /// The names of the paired devices.
    static func pairedNames() -> [String] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.compactMap(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The names of the paired devices that are connected now.
    static func connectedNames() -> Set<String> {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return Set(devices.filter { $0.isConnected() }.compactMap(\.name))
    }

    func start() {
        guard connectNotification == nil else {
            return
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            watchDisconnect(of: device)
        }
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
    }

    private func watchDisconnect(of device: IOBluetoothDevice) {
        if let notification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        ) {
            disconnectNotifications.append(notification)
        }
    }

    // IOBluetooth calls both callbacks on its own coordinator queue, not on the main queue, so
    // they are `nonisolated` and hop to the main actor before they touch any state. The two
    // IOBluetooth objects are only handed over, never used from two threads at once.

    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        Task { @MainActor in
            self.watchDisconnect(of: device)
            self.onChange?()
        }
    }

    @objc private nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let notification = notification
        Task { @MainActor in
            notification.unregister()
            self.disconnectNotifications.removeAll { $0 === notification }
            self.onChange?()
        }
    }
}
