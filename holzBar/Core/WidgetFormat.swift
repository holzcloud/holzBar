//
//  WidgetFormat.swift
//  holzBar
//

import Foundation

/// The text of a widget and what the app needs to draw it.
nonisolated struct WidgetText: Equatable, Sendable {
    var string: String
    /// Whether the text is drawn muted: a countdown whose moment has passed (D-02).
    var isMuted = false
    /// The battery state the app shows as a symbol next to the text; only for the format that
    /// carries it.
    var batteryState: BatteryState?

    /// Whether the source could not be read and the text is only the en dash (D-13).
    var isUnavailable: Bool {
        string == WidgetFormat.unavailable
    }
}

/// Turns a reading into the text of a widget's preset, in the user's locale.
///
/// Presets use `Date.FormatStyle`, percent, byte count and duration styles, so the order of the
/// parts, the digits and the units follow the locale for free (D-09); there is no template
/// language. The width a text may take is known in advance (``widthSamples(for:locale:calendar:capacityBytes:)``),
/// so the status item can keep one width (D-12).
nonisolated enum WidgetFormat {
    /// What a source that cannot be read shows: an en dash, never an old value (D-13).
    static let unavailable = "\u{2013}"

    /// The text of a reading for a widget's source and preset.
    ///
    /// A reading that does not fit the source or the preset (a byte count for a percent preset, a
    /// number that is not finite) gives the en dash. A button's text is its title.
    static func text(
        for reading: WidgetReading,
        definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar
    ) -> WidgetText {
        if definition.kind == .button {
            return WidgetText(string: definition.buttonTitle)
        }
        if definition.kind == .script {
            // The script's line as it is: plain text, never parsed. The app cuts a line that is
            // wider than the fixed width with an ellipsis (D-12).
            guard case .line(let line) = reading, !line.isEmpty else {
                return WidgetText(string: unavailable)
            }
            return WidgetText(string: line)
        }
        let preset = definition.preset
        switch (definition.source, reading) {
        case (.dateTime, .date(let date)):
            let style = dateStyle(for: definition, locale: locale, calendar: calendar)
            return WidgetText(string: date.formatted(style))
        case (.battery, .battery(let percent, let state)):
            let string = percentText(Double(min(max(percent, 0), 100)) / 100, locale: locale)
            return WidgetText(string: string, batteryState: preset == .percentAndState ? state : nil)
        case (.cpu, .fraction(let fraction)),
            (.memory, .fraction(let fraction)) where preset != .gigabytesUsed,
            (.freeDisk, .fraction(let fraction)) where preset != .gigabytesFree:
            guard fraction.isFinite else {
                break
            }
            return WidgetText(string: percentText(fraction, locale: locale))
        case (.memory, .bytes(let bytes)) where preset == .gigabytesUsed:
            return WidgetText(string: byteText(bytes, style: .memory, locale: locale))
        case (.freeDisk, .bytes(let bytes)) where preset == .gigabytesFree:
            return WidgetText(string: byteText(bytes, style: .file, locale: locale))
        case (.uptime, .duration(let duration)):
            let string = durationText(duration, roundingUp: false, compact: preset == .compactDuration, locale: locale)
            return WidgetText(string: string)
        case (.countdown, .countdown(let remaining, let isPassed)):
            let shown = isPassed ? .zero : remaining
            let string = durationText(shown, roundingUp: true, compact: preset == .compactDuration, locale: locale)
            return WidgetText(string: string, isMuted: isPassed)
        default:
            break
        }
        return WidgetText(string: unavailable)
    }

    /// The widest texts a widget's format can show, so that the app measures them once and sets
    /// one fixed width for the status item (D-12). The list has no duplicates.
    ///
    /// - A clock: every day of the leap year 2024 at 10:58:58 and at 22:58:58 in the calendar's
    ///   time zone, which holds every weekday name, every month name and both AM and PM forms.
    /// - A percent: 100 percent.
    /// - A byte count: the capacity, 9.9 GB and 999.9 GB.
    /// - A duration: 0 min, 1 min, 59 min, 1 h 1 min, 23 h 59 min, 1 day 1 h, 1 day 1 min,
    ///   99 days 23 h, 99 days 59 min, 999 days 23 h and 999 days 59 min.
    /// - A button: its title.
    /// - A script widget: 8, 16 or 32 zeros for its width (``scriptWidthDigits(for:)``). Digits
    ///   are as wide as each other in the widget font, so the width is fixed per format.
    ///
    /// - Parameter capacityBytes: The memory or the volume the count is a part of, when known.
    static func widthSamples(
        for definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar,
        capacityBytes: UInt64?
    ) -> [String] {
        var samples = [String]()
        var seen = Set<String>()
        func add(_ string: String) {
            if seen.insert(string).inserted {
                samples.append(string)
            }
        }
        if definition.kind == .button {
            if !definition.buttonTitle.isEmpty {
                add(definition.buttonTitle)
            }
            return samples
        }
        if definition.kind == .script {
            return [String(repeating: "0", count: scriptWidthDigits(for: definition.preset))]
        }
        let preset = definition.preset
        switch definition.source {
        case .dateTime:
            let style = dateStyle(for: definition, locale: locale, calendar: calendar)
            // 2024-01-01 at 00:00 UTC, in seconds since the reference date.
            let start = Date(timeIntervalSinceReferenceDate: 725_760_000)
            for day in 0..<366 {
                let date = start.addingTimeInterval(Double(day) * 86_400)
                for hour in [10, 22] {
                    if let moment = calendar.date(bySettingHour: hour, minute: 58, second: 58, of: date) {
                        add(moment.formatted(style))
                    }
                }
            }
        case .battery, .cpu:
            add(percentText(1, locale: locale))
        case .memory, .freeDisk:
            if preset == .gigabytesUsed || preset == .gigabytesFree {
                let style: ByteCountFormatStyle.Style = definition.source == .memory ? .memory : .file
                let gigabyte: Double = definition.source == .memory ? 1_073_741_824 : 1_000_000_000
                if let capacityBytes {
                    add(byteText(capacityBytes, style: style, locale: locale))
                }
                for gigabytes in [9.9, 999.9] {
                    add(byteText(UInt64(gigabytes * gigabyte), style: style, locale: locale))
                }
            } else {
                add(percentText(1, locale: locale))
            }
        case .uptime, .countdown:
            let minute = 60.0
            let hour = 60 * minute
            let day = 24 * hour
            // A zero unit is left out, so days can come with minutes ("999 days, 59 min").
            let durations = [
                0, minute, 59 * minute, hour + minute, 23 * hour + 59 * minute, day + hour, day + minute,
                99 * day + 23 * hour, 99 * day + 59 * minute, 999 * day + 23 * hour, 999 * day + 59 * minute,
            ]
            for seconds in durations {
                add(
                    durationText(
                        .seconds(seconds),
                        roundingUp: definition.source == .countdown,
                        compact: preset == .compactDuration,
                        locale: locale
                    )
                )
            }
        }
        return samples
    }

    /// How many digits wide a script widget's text is for a width (D-12, D-23): 8 narrow, 16
    /// medium and 32 wide. A format that is not a width gets the medium one.
    static func scriptWidthDigits(for preset: WidgetPreset) -> Int {
        switch preset {
        case .narrowText: 8
        case .wideText: 32
        default: 16
        }
    }

    /// Whether the locale shows the time on a 24-hour clock, told by whether 15:00 formatted
    /// with the shortened time style contains "15".
    static func prefers24HourClock(locale: Locale) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: 15)
        guard let date = calendar.date(from: components) else {
            return false
        }
        let style = Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        return date.formatted(style).contains("15")
    }

    // MARK: Parts

    /// The date style of a clock preset, with the hour cycle the widget asks for forced onto the
    /// locale, in the calendar's time zone.
    private static func dateStyle(
        for definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar
    ) -> Date.FormatStyle {
        var components = Locale.Components(locale: locale)
        components.hourCycle = definition.uses24HourClock ? .zeroToTwentyThree : .oneToTwelve
        var style = Date.FormatStyle(
            locale: Locale(components: components),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        switch definition.preset {
        case .weekdayAndTime:
            style = style.weekday(.abbreviated)
        case .dateAndTime:
            style = style.month(.abbreviated).day()
        case .weekdayDateAndTime:
            style = style.weekday(.abbreviated).month(.abbreviated).day()
        default:
            break
        }
        style = style.hour().minute()
        if definition.showsSeconds {
            style = style.second()
        }
        return style
    }

    /// A share as a whole percent in the locale's form, kept between 0 and 100 percent.
    private static func percentText(_ fraction: Double, locale: Locale) -> String {
        let shown = min(max(fraction, 0), 1)
        let style = FloatingPointFormatStyle<Double>.Percent(locale: locale).precision(.fractionLength(0))
        return shown.formatted(style)
    }

    private static func byteText(_ bytes: UInt64, style: ByteCountFormatStyle.Style, locale: Locale) -> String {
        Int64(clamping: bytes).formatted(ByteCountFormatStyle(style: style, locale: locale))
    }

    /// The time in days, hours and minutes, at most two of them (3 days 5 hr, 4 hr 13 min), with
    /// the smallest unit shown rounded down for a time that has run (uptime) and up for a time
    /// that is left (countdown), so a countdown never shows less than is left.
    private static func durationText(
        _ duration: Duration,
        roundingUp: Bool,
        compact: Bool,
        locale: Locale
    ) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes],
            width: compact ? .narrow : .abbreviated,
            maximumUnitCount: 2,
            fractionalPart: .hide(rounded: roundingUp ? .up : .down)
        ).locale(locale)
        return duration.formatted(style)
    }
}
