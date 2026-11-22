//
//  AlertTexts.swift
//  holzBar
//

import Foundation

/// The texts of System alerts that are drawn from values: how long a condition has to hold and what
/// a threshold or level reads, and the alert's own texts: its title, its detail line, the title of
/// its recovery and the short value beside its symbol. Values only, never an app, a device or a
/// user name (T-95-03); a rule's name is the settings entry's label, not an alert text.
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
    /// load and for the Mac battery, the level word for memory pressure and the thermal state
    /// (never degrees, D-13) and decimal gigabytes such as "10 GB" for free disk space.
    static func limitText(_ limit: Int, for signal: AlertSignal) -> String {
        switch signal {
        case .cpu, .macBattery:
            AccessoryBattery.percentText(limit)
        case .memoryPressure:
            switch limit {
            case 2: String(localized: "Critical")
            default: String(localized: "Warning")
            }
        case .thermal:
            switch limit {
            case 1: String(localized: "Fair")
            case 3: String(localized: "Critical")
            default: String(localized: "Serious")
            }
        case .freeDisk:
            (Int64(limit) * ThresholdRule.bytesPerGigabyte).formatted(ByteCountFormatStyle(style: .file))
        }
    }

    // MARK: The alert

    /// The word of the done state of an alert (the existing "Normal").
    static var normalText: String {
        String(localized: "Normal")
    }

    /// The title of a firing alert: what VoiceOver says once and the list shows. The closed notch
    /// never draws it.
    static func title(for snapshot: AlertSnapshot) -> String {
        switch snapshot.signal {
        case .cpu:
            String(localized: "CPU load high")
        case .memoryPressure, .thermal, .freeDisk, .macBattery:
            // The texts of these signals come with their signals.
            ""
        }
    }

    /// The title of an alert that cleared: "<rule> back to normal".
    static func recoveredTitle(for signal: AlertSignal) -> String {
        switch signal {
        case .cpu:
            String(localized: "CPU load back to normal")
        case .memoryPressure, .thermal, .freeDisk, .macBattery:
            ""
        }
    }

    /// The detail line of a firing alert, from the rule in force: what it watches for, as values.
    static func body(for snapshot: AlertSnapshot, rule: ThresholdRule) -> String {
        switch snapshot.signal {
        case .cpu:
            let limit = limitText(rule.limit, for: .cpu)
            if rule.hold == .immediately {
                return String(format: String(localized: "Above %@"), limit)
            }
            return String(format: String(localized: "Above %1$@ for %2$@"), limit, holdText(rule.hold))
        case .memoryPressure, .thermal, .freeDisk, .macBattery:
            return ""
        }
    }

    /// The short value beside the symbol: a whole percent, a decimal byte count or a level word.
    static func shortValue(_ value: AlertShortValue) -> String {
        switch value {
        case .percent(let percent):
            AccessoryBattery.percentText(percent)
        case .bytes(let bytes):
            bytes.formatted(ByteCountFormatStyle(style: .file))
        case .pressure(let pressure):
            switch pressure {
            case .normal: String(localized: "Normal")
            case .warning: String(localized: "Warning")
            case .critical: String(localized: "Critical")
            }
        case .thermal(let state):
            switch state {
            case .nominal: String(localized: "Normal")
            case .fair: String(localized: "Fair")
            case .serious: String(localized: "Serious")
            case .critical: String(localized: "Critical")
            }
        }
    }
}
