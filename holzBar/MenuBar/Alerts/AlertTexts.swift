//
//  AlertTexts.swift
//  holzBar
//

import Foundation

/// The texts of System alerts that are drawn from values: how long a condition has to hold and what
/// a threshold or level reads. Values only, never a rule's name (that is the settings entry's
/// label). The alert's own texts join them in the plan that shows the alert.
@MainActor
enum AlertTexts {
    /// How long a condition has to hold: "Immediately" for none, else the duration in words in the
    /// user's language, such as "5 minutes". Only "Immediately" is a catalogue string; the rest is
    /// drawn by the system's formatter.
    static func holdText(_ hold: AlertHold) -> String {
        if hold == .immediately {
            return String(localized: "Immediately")
        }
        return hold.duration.formatted(
            Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds], width: .wide)
        )
    }

    /// A rule's threshold or level as a value: a whole percent in the user's percent style for CPU
    /// load and for the Mac battery.
    static func limitText(_ limit: Int, for signal: AlertSignal) -> String {
        switch signal {
        case .cpu, .macBattery:
            AccessoryBattery.percentText(limit)
        case .memoryPressure, .thermal, .freeDisk:
            String(limit)
        }
    }
}
