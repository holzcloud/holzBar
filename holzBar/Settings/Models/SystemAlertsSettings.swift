//
//  SystemAlertsSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the System alerts module's rule settings: the five fixed rules, each with a switch,
/// a threshold or level and how long the condition has to hold (D-10 to D-13). A rule can be
/// neither added, removed nor reordered.
///
/// The defaults hold anything (a hand-edited file, an import, any process of the user), so every
/// stored value passes ``ThresholdRule/validatedLimit(_:for:)`` and ``AlertHold/snapped(seconds:)``
/// before it is a rule's value (T-95-05). Every setter validates its argument and writes only its
/// own key. The model runs nothing: whatever measures and evaluates the rules reads ``rules``.
@MainActor
@Observable
final class SystemAlertsSettings {
    /// The identifier of the System alerts module in ``ModuleCatalog``.
    static let moduleID = AlertLook.moduleID

    /// Whether this Mac has an internal battery, asked once, the first time it is needed. A Mac
    /// without one has no Mac battery rule to set and none to evaluate.
    static let hasInternalBattery = PowerSources.internalBattery() != nil

    /// The five rules in ``AlertSignal`` order: the defaults of D-11 and D-12 until the user
    /// stores a value.
    private(set) var rules: [ThresholdRule] = AlertSignal.allCases.map { ThresholdRule.defaultRule(for: $0) }

    /// The rule of a signal.
    func rule(for signal: AlertSignal) -> ThresholdRule {
        rules[Self.index(of: signal)]
    }

    /// Switches a rule on or off.
    func setOn(_ isOn: Bool, for signal: AlertSignal) {
        let index = Self.index(of: signal)
        guard rules[index].isOn != isOn else {
            return
        }
        rules[index].isOn = isOn
        Defaults.set(isOn, forKey: Self.keys(for: signal).isOn)
    }

    /// Sets a rule's threshold or level. A number the signal does not accept lands on the nearest
    /// one it does, or on the default level.
    func setLimit(_ limit: Int, for signal: AlertSignal) {
        let index = Self.index(of: signal)
        let validated = ThresholdRule.validatedLimit(limit, for: signal)
        guard rules[index].limit != validated else {
            return
        }
        rules[index].limit = validated
        Defaults.set(validated, forKey: Self.keys(for: signal).limit)
    }

    /// Sets how long a rule's condition has to hold.
    func setHold(_ hold: AlertHold, for signal: AlertSignal) {
        let index = Self.index(of: signal)
        guard rules[index].hold != hold else {
            return
        }
        rules[index].hold = hold
        Defaults.set(hold.rawValue, forKey: Self.keys(for: signal).hold)
    }

    /// The three keys of a rule's stored settings.
    static func keys(for signal: AlertSignal) -> (isOn: Defaults.Key, limit: Defaults.Key, hold: Defaults.Key) {
        switch signal {
        case .cpu:
            (.systemAlertsCPU, .systemAlertsCPUThreshold, .systemAlertsCPUHold)
        case .memoryPressure:
            (.systemAlertsMemoryPressure, .systemAlertsMemoryPressureLevel, .systemAlertsMemoryPressureHold)
        case .thermal:
            (.systemAlertsThermal, .systemAlertsThermalLevel, .systemAlertsThermalHold)
        case .freeDisk:
            (.systemAlertsFreeDisk, .systemAlertsFreeDiskThreshold, .systemAlertsFreeDiskHold)
        case .macBattery:
            (.systemAlertsMacBattery, .systemAlertsMacBatteryThreshold, .systemAlertsMacBatteryHold)
        }
    }

    /// Loads the stored settings. A value of the wrong type is ignored, a limit lands on what its
    /// signal accepts and a hold on the nearest preset (T-95-05).
    func performSetup(with appState: AppState) {
        for signal in AlertSignal.allCases {
            let keys = Self.keys(for: signal)
            let index = Self.index(of: signal)
            Defaults.ifPresent(key: keys.isOn) { (isOn: Bool) in
                rules[index].isOn = isOn
            }
            Defaults.ifPresent(key: keys.limit) { (limit: Int) in
                rules[index].limit = ThresholdRule.validatedLimit(limit, for: signal)
            }
            Defaults.ifPresent(key: keys.hold) { (seconds: Int) in
                rules[index].hold = AlertHold.snapped(seconds: seconds)
            }
        }
    }

    private static func index(of signal: AlertSignal) -> Int {
        // The rules are built from allCases, so every signal is found.
        AlertSignal.allCases.firstIndex(of: signal) ?? 0
    }
}
