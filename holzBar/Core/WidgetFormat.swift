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
    ///   99 days 23 h, 99 days 59 min, 999 days 23 h and 999 days 59 min. A countdown whose moment
    ///   lies more than 999 days away also gets its own widest texts, with a day count that
    ///   has one digit more than it can reach (WR-04): its moment may lie 126 years away.
    /// - A button: its title.
    /// - A script widget: 8, 16 or 32 zeros for its width (``scriptWidthDigits(for:)``). Digits
    ///   are as wide as each other in the widget font, so the width is fixed per format.
    ///
    /// - Parameters:
    ///   - capacityBytes: The memory or the volume the count is a part of, when known.
    ///   - now: The moment a countdown's remaining time is measured from. The remaining time only
    ///     shrinks, so the width measured now holds for as long as the widget exists.
    static func widthSamples(
        for definition: WidgetDefinition,
        locale: Locale,
        calendar: Calendar,
        capacityBytes: UInt64?,
        now: Date = .now
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
            var durations = [
                0, minute, 59 * minute, hour + minute, 23 * hour + 59 * minute, day + hour, day + minute,
                99 * day + 23 * hour, 99 * day + 59 * minute, 999 * day + 23 * hour, 999 * day + 59 * minute,
            ]
            // A countdown's moment may lie up to 126 years away, where the day count has four or
            // five digits (and a grouping separator): wider than every sample above. The day
            // count is measured from the actual moment, plus one because the last unit rounds up.
            if definition.source == .countdown, let target = definition.countdownTarget {
                let remaining = min(target.timeIntervalSince(now), WidgetDefinition.maximumCountdownDistance)
                if remaining.isFinite, remaining >= 1_000 * day {
                    let days = (remaining / day).rounded(.down) + 1
                    durations.append(days * day + 23 * hour)
                    durations.append(days * day + 59 * minute)
                }
            }
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

    /// Whether the locale shows the time on a 24-hour clock, told by its hour cycle.
    ///
    /// The locale is asked, not its output: a 24-hour locale whose digits are not Latin (Persian,
    /// Nepali, Burmese) shows "۱۵:۰۰", which holds no "15" to look for (WR-05). The hour cycle
    /// follows the locale's identifier and, for the current locale, the user's choice of a
    /// 24-hour time in System Settings.
    static func prefers24HourClock(locale: Locale) -> Bool {
        switch locale.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            true
        case .zeroToEleven, .oneToTwelve:
            false
        @unknown default:
            false
        }
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
