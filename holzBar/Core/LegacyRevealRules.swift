//
//  LegacyRevealRules.swift
//  holzBar
//

import Foundation

/// Turns the two fixed reveal rules of 0.0.7 and earlier ("when the battery is low", "when the
/// network connection is lost") into rules of the automation engine.
///
/// They were stored as one dictionary under `RevealRules`. The engine does the same work with one
/// observer per kind of event, and the user can now see, change and combine them in the
/// Automation pane.
nonisolated enum LegacyRevealRules {
    /// The levels the old stepper offered.
    private static let thresholds = 5...50

    /// The rules for the old settings that were on, in their order.
    ///
    /// - Parameters:
    ///   - stored: The dictionary stored under `RevealRules`.
    ///   - batteryName: The name for the low-battery rule.
    ///   - offlineName: The name for the offline rule.
    static func rules(from stored: [String: Any], batteryName: String, offlineName: String) -> [AutomationRule] {
        var rules = [AutomationRule]()
        if stored["LowBattery"] as? Bool == true {
            let level = stored["LowBatteryThreshold"] as? Int ?? 20
            let threshold = min(max(level, thresholds.lowerBound), thresholds.upperBound)
            // The old rule looked at the battery only while it discharged; unplugged and below
            // the level is the same question.
            rules.append(AutomationRule(
                name: batteryName,
                clauses: [
                    AutomationClause(condition: .power(.battery)),
                    AutomationClause(condition: .batteryBelow(threshold)),
                ],
                action: .showSection(.hidden),
                restoresWhenEnded: false
            ))
        }
        if stored["Offline"] as? Bool == true {
            rules.append(AutomationRule(
                name: offlineName,
                clauses: [AutomationClause(condition: .network(.offline))],
                action: .showSection(.hidden),
                restoresWhenEnded: false
            ))
        }
        return rules
    }
}
