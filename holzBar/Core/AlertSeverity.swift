//
//  AlertSeverity.swift
//  holzBar
//

import Foundation

/// How serious an alert is: the tint of its symbol (D-17). Colour is never the only carrier: the
/// short value and the title say it too.
nonisolated enum AlertSeverity: Equatable, Sendable {
    /// The rule fires.
    case amber
    /// The value is at or past the midpoint between the threshold and the worst possible value, or
    /// the level is Critical.
    case red

    /// The severity of an observation under a rule.
    ///
    /// A numeric signal turns red at the midpoint between its threshold and its worst value: CPU
    /// load at `(limit + 100) / 2` (95 % at 90), free disk space at half the threshold (5 GB at
    /// 10 GB), the Mac battery at half the threshold (10 % at 20 %). A level signal is red at
    /// Critical and amber below it. An observation that does not fit the rule is amber.
    static func of(_ observation: AlertObservation, rule: ThresholdRule) -> AlertSeverity {
        switch observation {
        case .fraction(let fraction):
            guard let percent = AlertZone.cpuPercent(fraction) else {
                return .amber
            }
            return percent * 2 >= rule.limit + 100 ? .red : .amber
        case .pressure(let pressure):
            return pressure == .critical ? .red : .amber
        case .thermal(let state):
            return state == .critical ? .red : .amber
        case .freeBytes(let bytes):
            // `bytes * 2 <= threshold`, written so that no byte count can overflow.
            return bytes <= rule.thresholdBytes / 2 ? .red : .amber
        case .battery(let percent, _):
            return percent <= rule.limit / 2 ? .red : .amber
        case .unavailable:
            return .amber
        }
    }
}

/// The short value an alert shows beside its symbol (D-17): a number or a word, never a name. The
/// view formats it in the user's locale.
nonisolated enum AlertShortValue: Equatable, Sendable {
    /// A whole percent.
    case percent(Int)
    /// A free-space amount in bytes.
    case bytes(Int64)
    /// A memory pressure level word.
    case pressure(ReadoutPressure)
    /// A thermal state word.
    case thermal(ReadoutThermal)
}

/// How an alert looks as a live activity (D-17, D-20): its symbol, tint, priority and short value.
nonisolated enum AlertLook {
    /// The module identifier of every alert activity.
    static let moduleID = "system-alerts"
    /// The activity id of the test alert (D-16).
    static let testID = "test"
    /// The value the test alert shows.
    static let testPercent = 92
    /// The symbol of the test alert: the CPU look.
    static let testSymbol = "cpu"
    /// The symbol of a recovered alert.
    static let recoveredSymbol = "checkmark.circle"
    /// The tint of a recovered alert.
    static let recoveredTint = LiveActivityTint.green

    /// The SF Symbol of an alert: one per signal; the thermometer follows the state and the
    /// battery follows the severity.
    static func symbol(for snapshot: AlertSnapshot) -> String {
        switch snapshot.signal {
        case .cpu:
            return "cpu"
        case .memoryPressure:
            return "memorychip"
        case .thermal:
            if case .thermal(.fair) = snapshot.observation {
                return "thermometer.medium"
            }
            return "thermometer.high"
        case .freeDisk:
            return "internaldrive"
        case .macBattery:
            return snapshot.severity == .red ? "battery.0percent" : "battery.25percent"
        }
    }

    /// The tint of a severity: the theme's amber or red.
    static func tint(for severity: AlertSeverity) -> LiveActivityTint {
        switch severity {
        case .amber:
            .amber
        case .red:
            .red
        }
    }

    /// The priority among live activities (D-20): thermal state and the Mac battery 30, the others
    /// 25, above camera and microphone (20), accessory and download (10).
    static func priority(for signal: AlertSignal) -> Int {
        switch signal {
        case .thermal, .macBattery:
            30
        case .cpu, .memoryPressure, .freeDisk:
            25
        }
    }

    /// The activity id of the done state of a cleared alert: a new id, so VoiceOver hears the
    /// recovery once.
    static func recoveredID(of signal: AlertSignal) -> String {
        "\(signal.rawValue).recovered"
    }

    /// The done state of a cleared alert (D-18). It starts at the recovery, so it widens the closed
    /// notch for its done hold however long the alert lasted, and its own id makes VoiceOver hear
    /// it once (WR-02). The title and the short word come from the app (localized), so Core stays
    /// free of the string catalog.
    static func recovery(of signal: AlertSignal, title: String, compactValue: String, at now: Date) -> LiveActivity {
        LiveActivity(
            id: recoveredID(of: signal),
            moduleID: moduleID,
            kind: .other,
            symbol: recoveredSymbol,
            title: title,
            priority: priority(for: signal),
            startedAt: now,
            finishedAt: now,
            tint: recoveredTint,
            announcesItself: false,
            compactValue: compactValue,
            widenedSeconds: DesignTokens.Alert.widenedSeconds
        )
    }

    /// The value to show for an observation, or `nil` for one that has none.
    static func shortValue(of observation: AlertObservation) -> AlertShortValue? {
        switch observation {
        case .fraction(let fraction):
            AlertZone.cpuPercent(fraction).map { .percent($0) }
        case .pressure(let pressure):
            .pressure(pressure)
        case .thermal(let state):
            .thermal(state)
        case .freeBytes(let bytes):
            .bytes(bytes)
        case .battery(let percent, _):
            .percent(percent)
        case .unavailable:
            nil
        }
    }
}
