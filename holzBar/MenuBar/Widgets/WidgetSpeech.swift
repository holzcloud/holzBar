//
//  WidgetSpeech.swift
//  holzBar
//

import Foundation

/// What VoiceOver says for a widget: a label (the source's name) and a value spoken in full,
/// or "unavailable" when the source could not be read (D-13, D-27).
///
/// The text in the menu bar is short ("80%", "3 d, 5 hr"); the value is the same reading in
/// words. Everything is built with `String(localized:)`, so it follows the language of the app.
nonisolated enum WidgetSpeech {
    /// The label of a widget: the name of its source, or a button's title, or "Shortcut" for a
    /// button that has none, or "Script" for a script widget, or the name of a built-in item
    /// (a launcher's is its application's, when it is known).
    static func label(for definition: WidgetDefinition, appName: String? = nil) -> String {
        switch definition.kind {
        case .builtIn:
            return label(for: definition.builtIn ?? .launcher, appName: appName)
        case .button:
            return definition.buttonTitle.isEmpty ? String(localized: "Shortcut") : definition.buttonTitle
        case .script:
            return String(localized: "Script")
        case .text:
            return label(for: definition.source)
        }
    }

    /// The name of a built-in item, as the settings and VoiceOver say it. A launcher is named
    /// after its application when that is known.
    static func label(for item: BuiltInItem, appName: String? = nil) -> String {
        switch item {
        case .focus: String(localized: "Focus")
        case .airDrop: String(localized: "AirDrop")
        case .media: String(localized: "Media Controls")
        case .userSwitching: String(localized: "Fast User Switching")
        case .timer: String(localized: "Timer")
        case .launcher: appName ?? String(localized: "App Launcher")
        }
    }

    /// The hint of a button: the name of its Shortcut, or "Choose a Shortcut" while it has none
    /// (D-27); of a built-in item: what a click does. A text widget has no action and no hint.
    ///
    /// - Parameters:
    ///   - definition: The widget.
    ///   - shortcutName: The Shortcut the button runs, kept on this Mac.
    ///   - appName: The application a launcher opens, when it is installed.
    static func hint(for definition: WidgetDefinition, shortcutName: String?, appName: String? = nil) -> String? {
        if definition.kind == .builtIn {
            return hint(for: definition.builtIn ?? .launcher, appName: appName)
        }
        guard definition.kind == .button else {
            return nil
        }
        return shortcutName ?? String(localized: "Choose a Shortcut")
    }

    /// What a click on a built-in item does, in a few words.
    static func hint(for item: BuiltInItem, appName: String?) -> String {
        switch item {
        case .focus: String(localized: "Opens Focus")
        case .airDrop: String(localized: "Opens AirDrop. Drop files here to share them.")
        case .media: String(localized: "Plays or pauses. Right-click for previous and next.")
        case .userSwitching: String(localized: "Opens fast user switching")
        case .timer: String(localized: "Starts or stops the timer")
        case .launcher:
            if let appName {
                String(localized: "Opens \(appName)")
            } else {
                String(localized: "Choose an app in the settings")
            }
        }
    }

    /// The name of a source. The same names are the titles in the settings.
    static func label(for source: WidgetSource) -> String {
        switch source {
        case .dateTime: String(localized: "Date and Time")
        case .battery: String(localized: "Battery")
        case .cpu: String(localized: "CPU Load")
        case .memory: String(localized: "Memory")
        case .uptime: String(localized: "Uptime")
        case .freeDisk: String(localized: "Free Disk Space")
        case .countdown: String(localized: "Countdown")
        case .networkSpeed: String(localized: "Network Speed")
        case .diskActivity: String(localized: "Disk Activity")
        case .thermalState: String(localized: "Thermal State")
        }
    }

    /// The value of a script widget: its line as the script wrote it, or what is missing: "Choose
    /// a script" while no script is chosen, "Allow this script in Automation, Scripts" while the
    /// gate refuses the one that is, and "unavailable" otherwise (D-13, D-23, D-27).
    ///
    /// - Parameters:
    ///   - reading: The last reading, a line or nothing.
    ///   - hasScript: Whether a script is chosen for the widget on this Mac.
    ///   - isRefused: Whether the gate refused the chosen script: not allowed, or changed since.
    static func scriptValue(for reading: WidgetReading, hasScript: Bool, isRefused: Bool) -> String {
        guard hasScript else {
            return String(localized: "Choose a script")
        }
        if isRefused {
            return String(localized: "Allow this script in Automation, Scripts")
        }
        if case .line(let line) = reading, !line.isEmpty {
            return line
        }
        return String(localized: "unavailable")
    }

    /// The value of a widget in full: "80 percent, charging", "16 gigabytes", "3 days, 5 hours".
    ///
    /// - Parameters:
    ///   - reading: What the source gave.
    ///   - definition: The widget; its preset decides which parts are spoken.
    ///   - locale: The language and the number format of the user.
    ///   - calendar: The calendar the date is written in.
    ///   - rateUnit: Whether the network speed is said in bytes or bits per second.
    static func value(
        for reading: WidgetReading,
        definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar,
        rateUnit: ReadoutRateUnit = .bytes
    ) -> String {
        if definition.kind == .button {
            // A button has no reading: VoiceOver says its label and its hint.
            return ""
        }
        if definition.kind == .builtIn {
            // Only the timer has a reading: the time it shows.
            if definition.builtIn == .timer, case .line(let line) = reading {
                return line
            }
            return ""
        }
        if definition.kind == .script {
            return scriptValue(for: reading, hasScript: true, isRefused: false)
        }
        let unavailable = String(localized: "unavailable")
        switch (definition.source, reading) {
        case (.dateTime, .date):
            return WidgetFormat.text(for: reading, definition: definition, locale: locale, calendar: calendar).string
        case (.battery, .battery), (.battery, .power):
            return batteryValue(for: reading, preset: definition.preset, locale: locale) ?? unavailable
        case (.thermalState, .thermal(let level)):
            let word = switch level {
            case .nominal: String(localized: "Nominal")
            case .fair: String(localized: "Fair")
            case .serious: String(localized: "Serious")
            case .critical: String(localized: "Critical")
            }
            return String(localized: "Thermal state \(word)")
        case (.cpu, .clusters(let loads)) where definition.preset == .perCluster:
            guard loads.count >= 2, loads.allSatisfy({ $0.load.isFinite }) else {
                return unavailable
            }
            return clusterValue(loads)
        case (.cpu, .fraction(let fraction)),
            (.memory, .fraction(let fraction)) where definition.preset == .percentUsed,
            (.freeDisk, .fraction(let fraction)) where definition.preset != .gigabytesFree:
            guard fraction.isFinite else {
                return unavailable
            }
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
            return String(localized: "\(percent) percent")
        case (.memory, .bytes(let bytes)) where definition.preset == .gigabytesUsed:
            // The text counts memory in units of 1024 cubed and calls them GB.
            return gigabytes(bytes, perGigabyte: 1_073_741_824, locale: locale)
        case (.freeDisk, .bytes(let bytes)) where definition.preset == .gigabytesFree:
            return gigabytes(bytes, perGigabyte: 1_000_000_000, locale: locale)
        case (.memory, .bytes(let bytes)) where definition.preset == .swapUsed:
            // Swap is counted like memory, in units of 1024 cubed.
            return String(localized: "Swap \(gigabytes(bytes, perGigabyte: 1_073_741_824, locale: locale))")
        case (.memory, .pressure(let pressure)) where definition.preset == .pressure:
            let word = switch pressure {
            case .normal: String(localized: "Normal")
            case .warning: String(localized: "High")
            case .critical: String(localized: "Critical")
            }
            return String(localized: "Memory pressure \(word)")
        case (.uptime, .duration(let duration)):
            return spoken(duration, roundingUp: false, locale: locale)
        case (.countdown, .countdown(let remaining, let isPassed)):
            return spoken(isPassed ? .zero : remaining, roundingUp: true, locale: locale)
        case (.networkSpeed, .rates(let first, let second)):
            guard first.isFinite, second.isFinite, first >= 0, second >= 0 else {
                return unavailable
            }
            let download = spokenRate(first, unit: rateUnit, locale: locale)
            let upload = spokenRate(second, unit: rateUnit, locale: locale)
            switch definition.preset {
            case .download: return String(localized: "Download \(download)")
            case .upload: return String(localized: "Upload \(upload)")
            default: return String(localized: "Download \(download), upload \(upload)")
            }
        case (.diskActivity, .rates(let first, let second)):
            guard first.isFinite, second.isFinite, first >= 0, second >= 0 else {
                return unavailable
            }
            let read = spokenRate(first, locale: locale)
            let written = spokenRate(second, locale: locale)
            switch definition.preset {
            case .read: return String(localized: "Read \(read)")
            case .write: return String(localized: "Write \(written)")
            default: return String(localized: "Read \(read), write \(written)")
            }
        default:
            return unavailable
        }
    }

    /// The load of every core cluster in words: "Performance cores 42 percent, Efficiency cores
    /// 12 percent", in the kernel's level order. A level that is neither one names itself.
    static func clusterValue(_ loads: [ClusterLoad]) -> String {
        loads.map { cluster in
            let percent = Int((min(max(cluster.load, 0), 1) * 100).rounded())
            let value = String(localized: "\(percent) percent")
            switch cluster.label {
            case .performance: return String(localized: "Performance cores \(value)")
            case .efficiency: return String(localized: "Efficiency cores \(value)")
            case .other(let letter):
                let name = cluster.level.name.isEmpty ? letter : cluster.level.name
                return String(localized: "\(name) cores \(value)")
            }
        }
        .joined(separator: ", ")
    }

    /// The battery in words: "80 percent, on battery, 2 hours, 10 minutes left", or the adapter's
    /// power. `nil` for a value the format cannot say (an adapter without watts).
    static func batteryValue(for reading: WidgetReading, preset: WidgetPreset, locale: Locale) -> String? {
        let power: PowerReading
        switch reading {
        case .battery(let percent, let state):
            power = PowerReading(percent: percent, state: state)
        case .power(let value):
            power = value
        default:
            return nil
        }
        if preset == .adapterWatts {
            guard let watts = power.adapterWatts else {
                return nil
            }
            let style = Measurement<UnitPower>.FormatStyle(
                width: .wide,
                locale: locale,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            let amount = Measurement(value: Double(watts), unit: UnitPower.watts).formatted(style)
            return String(localized: "\(amount) adapter")
        }
        let level = min(max(power.percent, 0), 100)
        guard preset != .percent else {
            return String(localized: "\(level) percent")
        }
        let phrase = switch power.state {
        case .charging: String(localized: "\(level) percent, charging")
        case .charged: String(localized: "\(level) percent, charged")
        case .onBattery: String(localized: "\(level) percent, on battery")
        case .onAdapter: String(localized: "\(level) percent, on power adapter")
        }
        guard preset == .percentAndTimeLeft else {
            return phrase
        }
        switch power.state {
        case .onBattery:
            return power.timeToEmpty.map { phrase + ", " + String(localized: "\(spoken($0, roundingUp: false, locale: locale)) left") }
                ?? phrase
        case .charging:
            return power.timeToFull.map { phrase + ", " + String(localized: "\(spoken($0, roundingUp: false, locale: locale)) to full") }
                ?? phrase
        case .charged, .onAdapter:
            return phrase
        }
    }

    /// A rate in words, in the unit that fits its size: "1.2 megabytes per second".
    static func spokenRate(_ bytesPerSecond: Double, unit: ReadoutRateUnit = .bytes, locale: Locale) -> String {
        let units: [UnitInformationStorage] = unit == .bits
            ? [.kilobits, .megabits, .gigabits]
            : [.kilobytes, .megabytes, .gigabytes]
        var scaled = (unit == .bits ? bytesPerSecond * 8 : bytesPerSecond) / 1_000
        var index = 0
        while scaled >= 999.5, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        let style = Measurement<UnitInformationStorage>.FormatStyle(
            width: .wide,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...1))
        )
        let amount = Measurement(value: scaled, unit: units[index]).formatted(style)
        return String(localized: "\(amount) per second")
    }

    static func gigabytes(_ bytes: UInt64, perGigabyte: Double, locale: Locale) -> String {
        let measurement = Measurement(value: Double(bytes) / perGigabyte, unit: UnitInformationStorage.gigabytes)
        let style = Measurement<UnitInformationStorage>.FormatStyle(
            width: .wide,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...1))
        )
        return measurement.formatted(style)
    }

    /// Days, hours and minutes in words, at most two units, rounded the way the text is.
    static func spoken(_ duration: Duration, roundingUp: Bool, locale: Locale) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes],
            width: .wide,
            maximumUnitCount: 2,
            fractionalPart: .hide(rounded: roundingUp ? .up : .down)
        ).locale(locale)
        return duration.formatted(style)
    }
}
