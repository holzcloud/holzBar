//
//  AlertRequestPlan.swift
//  holzBar
//

import Foundation

/// What System alerts ask the shared monitor to measure (D-03).
///
/// The alerts are the one `.background` consumer of the system readouts ledger: the hub's tiles and
/// the widgets are `.visible` consumers. ``request(rules:isModuleOn:hasBattery:)`` builds the whole
/// request from the rules, and `nil` means that nothing is measured for alerts: the module is off,
/// or no shown rule is on, so the ledger stays idle and the monitor has no tick and no observer
/// (MON-08 extended to alerts).
nonisolated enum AlertRequestPlan {
    /// The consumer id of the alerts in the ledger.
    static let consumerID = "alerts"
    /// The seconds between two readings while the CPU rule is on; two samples fit inside the clear
    /// hold even in Low Power Mode (which doubles it).
    static let cpuIntervalSeconds = 10
    /// The seconds between two readings when no CPU rule is on: the event metrics follow their
    /// events, and the free disk space is kept for a minute anyway.
    static let eventIntervalSeconds = 60

    /// The metric a signal reads.
    static func metric(for signal: AlertSignal) -> ReadoutMetric {
        switch signal {
        case .cpu:
            .cpu
        case .memoryPressure:
            .memoryPressure
        case .thermal:
            .thermal
        case .freeDisk:
            .diskSpace
        case .macBattery:
            .power
        }
    }

    /// The request of the alerts, or `nil` when nothing is to be measured. The Mac battery rule
    /// counts only on a Mac with an internal battery.
    static func request(rules: [ThresholdRule], isModuleOn: Bool, hasBattery: Bool) -> ReadoutRequest? {
        guard isModuleOn else {
            return nil
        }
        let active = rules.filter { $0.isOn && ($0.signal != .macBattery || hasBattery) }
        guard !active.isEmpty else {
            return nil
        }
        let readsCPU = active.contains { $0.signal == .cpu }
        return ReadoutRequest(
            metrics: Set(active.map { metric(for: $0.signal) }),
            intervalSeconds: readsCPU ? cpuIntervalSeconds : eventIntervalSeconds,
            needsBaseline: readsCPU
        )
    }
}
