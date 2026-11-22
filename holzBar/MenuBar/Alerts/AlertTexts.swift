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
    /// never draws it. Memory pressure and the thermal state follow the level they are at now.
    static func title(for snapshot: AlertSnapshot) -> String {
        switch snapshot.signal {
        case .cpu:
            return String(localized: "CPU load high")
        case .memoryPressure:
            if case .pressure(.critical) = snapshot.observation {
                return String(localized: "Memory pressure critical")
            }
            return String(localized: "Memory pressure high")
        case .thermal:
            let word = if case .thermal(let state) = snapshot.observation {
                thermalWord(state)
            } else {
                thermalWord(.serious)
            }
            return String(localized: "Thermal state \(word)")
        case .freeDisk:
            return String(localized: "Disk space low")
        case .macBattery:
            return String(localized: "Mac battery low")
        }
    }

    /// The title of an alert that cleared: "<rule> back to normal".
    static func recoveredTitle(for signal: AlertSignal) -> String {
        switch signal {
        case .cpu:
            String(localized: "CPU load back to normal")
        case .memoryPressure:
            String(localized: "Memory pressure back to normal")
        case .thermal:
            String(localized: "Thermal state back to normal")
        case .freeDisk:
            String(localized: "Disk space back to normal")
        case .macBattery:
            String(localized: "Mac battery back to normal")
        }
    }

    /// The detail line of a firing alert, from the rule in force and the latest reading: what the
    /// rule watches for, as values. The thermal state is never shown in degrees (D-13).
    static func body(for snapshot: AlertSnapshot, rule: ThresholdRule) -> String {
        switch snapshot.signal {
        case .cpu:
            let limit = limitText(rule.limit, for: .cpu)
            if rule.hold == .immediately {
                return String(format: String(localized: "Above %@"), limit)
            }
            return String(format: String(localized: "Above %1$@ for %2$@"), limit, holdText(rule.hold))
        case .memoryPressure:
            let isCritical = rule.pressureLevel == .critical
            if rule.hold == .immediately {
                return isCritical ? String(localized: "Critical level") : String(localized: "Warning level")
            }
            let format = isCritical ? String(localized: "Critical level for %@") : String(localized: "Warning level for %@")
            return String(format: format, holdText(rule.hold))
        case .thermal:
            guard case .thermal(let state) = snapshot.observation else {
                return ""
            }
            switch state {
            case .nominal: return ""
            case .fair: return String(localized: "The Mac runs warm.")
            case .serious: return String(localized: "The Mac runs hot and may slow down.")
            case .critical: return String(localized: "The Mac is too hot and is slowing down.")
            }
        case .freeDisk:
            guard case .freeBytes(let bytes) = snapshot.observation else {
                return ""
            }
            return String(format: String(localized: "%@ free"), shortValue(.bytes(bytes)))
        case .macBattery:
            guard case .battery(let percent, _) = snapshot.observation else {
                return ""
            }
            // The charge, not the time left.
            return String(format: String(localized: "%@ left"), shortValue(.percent(percent)))
        }
    }

    /// The word of a thermal state.
    private static func thermalWord(_ state: ReadoutThermal) -> String {
        switch state {
        case .nominal: String(localized: "Nominal")
        case .fair: String(localized: "Fair")
        case .serious: String(localized: "Serious")
        case .critical: String(localized: "Critical")
        }
    }

    /// The short value beside the symbol: a whole percent, a decimal byte count or a level word.
    static func shortValue(_ value: AlertShortValue) -> String {
        switch value {
        case .percent(let percent):
            return AccessoryBattery.percentText(percent)
        case .bytes(let bytes):
            return bytes.formatted(ByteCountFormatStyle(style: .file))
        case .pressure(let pressure):
            switch pressure {
            case .normal: return normalText
            case .warning: return String(localized: "Warning")
            case .critical: return String(localized: "Critical")
            }
        case .thermal(let state):
            if state == .nominal {
                return normalText
            }
            return thermalWord(state)
        }
    }
}
