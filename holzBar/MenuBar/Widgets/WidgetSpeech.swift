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
    /// button that has none.
    static func label(for definition: WidgetDefinition) -> String {
        if definition.kind == .button {
            return definition.buttonTitle.isEmpty ? String(localized: "Shortcut") : definition.buttonTitle
        }
        return label(for: definition.source)
    }

    /// The hint of a button: the name of its Shortcut, or "Choose a Shortcut" while it has none
    /// (D-27). A text widget has no action and no hint.
    ///
    /// - Parameters:
    ///   - definition: The widget.
    ///   - shortcutName: The Shortcut the button runs, kept on this Mac.
    static func hint(for definition: WidgetDefinition, shortcutName: String?) -> String? {
        guard definition.kind == .button else {
            return nil
        }
        return shortcutName ?? String(localized: "Choose a Shortcut")
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
        }
    }

    /// The value of a widget in full: "80 percent, charging", "16 gigabytes", "3 days, 5 hours".
    ///
    /// - Parameters:
    ///   - reading: What the source gave.
    ///   - definition: The widget; its preset decides which parts are spoken.
    ///   - locale: The language and the number format of the user.
    ///   - calendar: The calendar the date is written in.
    static func value(
        for reading: WidgetReading,
        definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        if definition.kind == .button {
            // A button has no reading: VoiceOver says its label and its hint.
            return ""
        }
        let unavailable = String(localized: "unavailable")
        switch (definition.source, reading) {
        case (.dateTime, .date):
            return WidgetFormat.text(for: reading, definition: definition, locale: locale, calendar: calendar).string
        case (.battery, .battery(let percent, let state)):
            let level = min(max(percent, 0), 100)
            guard definition.preset == .percentAndState else {
                return String(localized: "\(level) percent")
            }
            switch state {
            case .charging: return String(localized: "\(level) percent, charging")
            case .charged: return String(localized: "\(level) percent, charged")
            case .onBattery: return String(localized: "\(level) percent, on battery")
            case .onAdapter: return String(localized: "\(level) percent, on power adapter")
            }
        case (.cpu, .fraction(let fraction)),
            (.memory, .fraction(let fraction)) where definition.preset != .gigabytesUsed,
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
        case (.uptime, .duration(let duration)):
            return spoken(duration, roundingUp: false, locale: locale)
        case (.countdown, .countdown(let remaining, let isPassed)):
            return spoken(isPassed ? .zero : remaining, roundingUp: true, locale: locale)
        default:
            return unavailable
        }
    }

    private static func gigabytes(_ bytes: UInt64, perGigabyte: Double, locale: Locale) -> String {
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
    private static func spoken(_ duration: Duration, roundingUp: Bool, locale: Locale) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes],
            width: .wide,
            maximumUnitCount: 2,
            fractionalPart: .hide(rounded: roundingUp ? .up : .down)
        ).locale(locale)
        return duration.formatted(style)
    }
}
