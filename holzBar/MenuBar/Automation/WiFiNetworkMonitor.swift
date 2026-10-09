//
//  WiFiNetworkMonitor.swift
//  holzBar
//

import CoreLocation
import CoreWLAN
import Observation

/// Reads the name of the Wi-Fi network for the automation rules.
///
/// Since macOS 14 the system gives the network name only to apps that may use Location
/// Services, so the condition "Wi-Fi network named …" is the one condition that needs a
/// permission. holzBar asks for it only when the user adds that condition, and says why
/// first. It reads the name, never the location: no location updates are requested. Without
/// the permission the name is unknown and the condition is never true.
@MainActor
@Observable
final class WiFiNetworkMonitor: NSObject, CLLocationManagerDelegate, CWEventDelegate {
    /// The name of the network the Mac is connected to, or `nil` when it is not connected
    /// or holzBar may not read it.
    private(set) var networkName: String?

    /// The state of the Location Services permission.
    private(set) var authorization = CLAuthorizationStatus.notDetermined

    /// Called when the name or the permission changed.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var locationManager: CLLocationManager?
    @ObservationIgnored private var isMonitoring = false

    /// Whether holzBar may read the network name.
    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Starts following the network name and the permission.
    func start() {
        guard !isMonitoring else {
            return
        }
        isMonitoring = true
        let manager = locationManager ?? CLLocationManager()
        manager.delegate = self
        locationManager = manager
        let client = CWWiFiClient.shared()
        client.delegate = self
        try? client.startMonitoringEvent(with: .ssidDidChange)
        refresh()
    }

    /// Stops following them.
    func stop() {
        guard isMonitoring else {
            return
        }
        isMonitoring = false
        let client = CWWiFiClient.shared()
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
        locationManager?.delegate = nil
    }

    /// Asks the system for Location Services, once, when the user has not answered yet.
    /// The system shows its own question; holzBar has explained it before this call.
    func requestAuthorization() {
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        manager.delegate = self
        guard manager.authorizationStatus == .notDetermined else {
            refresh()
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    /// The name of the network now, read for the field of the condition. `nil` without
    /// the permission.
    var currentName: String? {
        isAuthorized ? CWWiFiClient.shared().interface()?.ssid() : nil
    }

    /// Reads the permission and the name again.
    func refresh() {
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        authorization = manager.authorizationStatus
        networkName = currentName
        onChange?()
    }

    // MARK: Delegates

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refresh()
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            self.refresh()
        }
    }
}
