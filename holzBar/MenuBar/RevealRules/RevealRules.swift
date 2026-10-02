//
//  RevealRules.swift
//  holzBar
//

import Combine
import Foundation
import IOKit.ps
import Network
import OSLog

/// Shows the hidden section by itself when something needs attention
/// (jordanbaird/Ice#62): the battery runs low, or the Mac goes offline.
///
/// The section is shown for the "temporarily shown item" interval, then hidden
/// again. Each rule fires once when its condition starts, not again while it
/// lasts.
@MainActor
final class RevealRules: ObservableObject {
    /// Shows hidden items when the battery falls below ``lowBatteryThreshold``.
    @Published var revealsOnLowBattery = false {
        didSet { save() }
    }

    /// The battery level, in percent, below which hidden items are shown.
    @Published var lowBatteryThreshold = 20 {
        didSet { save() }
    }

    /// Shows hidden items when the network connection is lost.
    @Published var revealsWhenOffline = false {
        didSet { save() }
    }

    private let logger = Logger(category: "RevealRules")
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private let pathMonitor = NWPathMonitor()
    private var wasBatteryLow = false
    private var wasOffline = false
    private var isLoading = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        load()

        Timer.publish(every: 60, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkBattery()
            }
            .store(in: &cancellables)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor in
                self?.networkChanged(isOffline: isOffline)
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
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
                maximum > 0
            else {
                continue
            }
            return current * 100 / maximum
        }
        return nil
    }

    private func checkBattery() {
        guard revealsOnLowBattery else {
            wasBatteryLow = false
            return
        }
        let isLow = (Self.dischargingBatteryLevel() ?? 100) < lowBatteryThreshold
        if isLow, !wasBatteryLow {
            reveal(because: "the battery is low")
        }
        wasBatteryLow = isLow
    }

    private func networkChanged(isOffline: Bool) {
        if revealsWhenOffline, isOffline, !wasOffline {
            reveal(because: "the network connection was lost")
        }
        wasOffline = isOffline
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
            try await Task.sleep(for: .seconds(interval))
            if !section.isHidden {
                section.hide()
            }
        }
    }
}
