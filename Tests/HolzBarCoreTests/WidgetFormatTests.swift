import Foundation
import Testing
@testable import HolzBarCore

@Suite("WidgetFormat")
struct WidgetFormatTests {
    private let english = Locale(identifier: "en_US")
    private let swiss = Locale(identifier: "de_CH")
    private let german = Locale(identifier: "de_DE")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    /// Monday, 12 October 2026, 14:05:09 GMT.
    private var moment: Date {
        let components = DateComponents(year: 2026, month: 10, day: 12, hour: 14, minute: 5, second: 9)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Narrow and no-break spaces compared as plain spaces, so the tests hold whichever space the
    /// formatter's data uses.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func definition(
        _ source: WidgetSource,
        preset: WidgetPreset? = nil,
        uses24HourClock: Bool = false,
        showsSeconds: Bool = false
    ) -> WidgetDefinition {
        WidgetDefinition(
            id: UUID(),
            kind: .text,
            source: source,
            preset: preset ?? source.defaultPreset,
            uses24HourClock: uses24HourClock,
            showsSeconds: showsSeconds
        )
    }

    private func text(
        _ reading: WidgetReading,
        _ definition: WidgetDefinition,
        locale: Locale? = nil
    ) -> WidgetText {
        WidgetFormat.text(for: reading, definition: definition, locale: locale ?? english, calendar: calendar)
    }

    @Test("An unreadable source shows an en dash (D-13)")
    func unreadableShowsEnDash() {
        #expect(WidgetFormat.unavailable == "\u{2013}")
        for source in WidgetSource.allCases {
            let result = text(.unavailable, definition(source))
            #expect(result.string == "\u{2013}", "\(source)")
            #expect(result.isUnavailable)
            #expect(!result.isMuted)
            #expect(result.batteryState == nil)
        }
        // A reading that does not fit the source or the preset is no value either.
        #expect(text(.bytes(1000), definition(.cpu)).isUnavailable)
        #expect(text(.fraction(0.5), definition(.memory, preset: .gigabytesUsed)).isUnavailable)
        #expect(text(.bytes(1000), definition(.freeDisk, preset: .percentFree)).isUnavailable)
        #expect(text(.fraction(.nan), definition(.cpu)).isUnavailable)
        #expect(text(.fraction(.infinity), definition(.freeDisk, preset: .percentFree)).isUnavailable)
        #expect(text(.date(moment), definition(.battery)).isUnavailable)
    }

    @Test("A passed countdown shows zero minutes, muted (D-02)")
    func passedCountdown() {
        let passed = WidgetReading.countdown(remaining: .zero, isPassed: true)
        let abbreviated = text(passed, definition(.countdown))
        #expect(plain(abbreviated.string) == "0 min")
        #expect(abbreviated.isMuted)
        let compact = text(passed, definition(.countdown, preset: .compactDuration))
        #expect(plain(compact.string) == "0m")
        #expect(compact.isMuted)
        let running = text(.countdown(remaining: .seconds(90), isPassed: false), definition(.countdown))
        #expect(!running.isMuted)
        #expect(plain(running.string) == "2 min")
    }

    @Test("The clock follows the widget's hour cycle, with the weekday and date of its preset (D-09)")
    func clockPresets() {
        let reading = WidgetReading.date(moment)
        let twentyFour = text(reading, definition(.dateTime, uses24HourClock: true)).string
        #expect(plain(twentyFour) == "14:05")
        let twelve = plain(text(reading, definition(.dateTime)).string)
        #expect(twelve.contains("2:05"))
        #expect(twelve.contains("PM"))
        let weekday = plain(text(reading, definition(.dateTime, preset: .weekdayAndTime, uses24HourClock: true)).string)
        #expect(weekday.hasPrefix("Mon"))
        #expect(weekday.contains("14:05"))
        let date = plain(text(reading, definition(.dateTime, preset: .dateAndTime, uses24HourClock: true)).string)
        #expect(date.contains("Oct"))
        #expect(date.contains("12"))
        #expect(!date.contains("Mon"))
        let everything = plain(
            text(reading, definition(.dateTime, preset: .weekdayDateAndTime, uses24HourClock: true)).string
        )
        #expect(everything.hasPrefix("Mon"))
        #expect(everything.contains("Oct"))
        #expect(everything.contains("14:05"))
    }

    @Test("Seconds are added only when the clock asks for them (D-10)")
    func clockSeconds() {
        let reading = WidgetReading.date(moment)
        let with = plain(text(reading, definition(.dateTime, uses24HourClock: true, showsSeconds: true)).string)
        #expect(with == "14:05:09")
        let without = plain(text(reading, definition(.dateTime, uses24HourClock: true)).string)
        #expect(!without.contains("09"))
    }

    @Test("The hour cycle follows the widget, not the locale")
    func hourCycleFollowsTheWidget() {
        let reading = WidgetReading.date(moment)
        let twelve = plain(text(reading, definition(.dateTime), locale: swiss).string)
        #expect(twelve.contains("PM"))
        let twentyFour = plain(text(reading, definition(.dateTime, uses24HourClock: true), locale: english).string)
        #expect(!twentyFour.contains("PM"))
        #expect(twentyFour.contains("14"))
    }

    @Test("The 24-hour preference comes from the locale")
    func prefers24HourClock() {
        #expect(!WidgetFormat.prefers24HourClock(locale: english))
        #expect(WidgetFormat.prefers24HourClock(locale: swiss))
        #expect(WidgetFormat.prefers24HourClock(locale: german))
    }

    @Test("Battery gives the locale's percent and carries the state only when the preset shows it")
    func battery() {
        let reading = WidgetReading.battery(percent: 80, state: .charging)
        let percentOnly = text(reading, definition(.battery, preset: .percent))
        #expect(plain(percentOnly.string) == "80%")
        #expect(percentOnly.batteryState == nil)
        let withState = text(reading, definition(.battery, preset: .percentAndState))
        #expect(plain(withState.string) == "80%")
        #expect(withState.batteryState == .charging)
        #expect(plain(text(.battery(percent: 140, state: .charged), definition(.battery)).string) == "100%")
        #expect(plain(text(.battery(percent: 5, state: .onBattery), definition(.battery), locale: german).string) == "5 %")
    }

    @Test("CPU, memory and disk give a percent or a byte count")
    func percentAndBytes() {
        #expect(plain(text(.fraction(0.374), definition(.cpu)).string) == "37%")
        #expect(plain(text(.fraction(1.5), definition(.cpu)).string) == "100%")
        #expect(plain(text(.fraction(0.5), definition(.memory)).string) == "50%")
        #expect(plain(text(.fraction(0.25), definition(.freeDisk, preset: .percentFree)).string) == "25%")
        let memory = plain(text(.bytes(10_950_000_000), definition(.memory, preset: .gigabytesUsed)).string)
        #expect(memory == "10.2 GB")
        let disk = plain(text(.bytes(120_400_000_000), definition(.freeDisk)).string)
        #expect(disk == "120.4 GB")
        let german = plain(text(.bytes(120_400_000_000), definition(.freeDisk), locale: german).string)
        #expect(german == "120,4 GB")
    }

    @Test("Uptime rounds down and a countdown rounds up, in at most two units")
    func durations() {
        let uptime = WidgetReading.duration(.seconds(4 * 3600 + 13 * 60 + 5))
        #expect(plain(text(uptime, definition(.uptime)).string) == "4 hr, 13 min")
        #expect(plain(text(uptime, definition(.uptime, preset: .compactDuration)).string) == "4h 13m")
        let left = WidgetReading.countdown(remaining: .seconds(4 * 3600 + 12 * 60 + 5), isPassed: false)
        #expect(plain(text(left, definition(.countdown)).string) == "4 hr, 13 min")
        let long = WidgetReading.duration(.seconds(3 * 86_400 + 5 * 3600 + 59 * 60))
        #expect(plain(text(long, definition(.uptime)).string) == "3 days, 5 hr")
        #expect(plain(text(long, definition(.uptime, preset: .compactDuration)).string) == "3d 5h")
        #expect(plain(text(.duration(.seconds(30)), definition(.uptime)).string) == "0 min")
        #expect(plain(text(.countdown(remaining: .seconds(30), isPassed: false), definition(.countdown)).string) == "1 min")
    }

    @Test("A button's text is its title")
    func buttonText() {
        let button = WidgetDefinition.button(title: "Focus")
        #expect(text(.unavailable, button).string == "Focus")
        let samples = WidgetFormat.widthSamples(for: button, locale: english, calendar: calendar, capacityBytes: nil)
        #expect(samples == ["Focus"])
        let empty = WidgetFormat.widthSamples(
            for: WidgetDefinition.button(title: ""),
            locale: english,
            calendar: calendar,
            capacityBytes: nil
        )
        #expect(empty.isEmpty)
    }

    @Test("The widest text of a format is among the samples (D-12)")
    func widestTextIsAmongTheSamples() {
        for locale in [english, swiss, german] {
            for uses24HourClock in [false, true] {
                for preset in WidgetSource.dateTime.presets {
                    let widget = definition(.dateTime, preset: preset, uses24HourClock: uses24HourClock, showsSeconds: true)
                    let samples = WidgetFormat.widthSamples(
                        for: widget, locale: locale, calendar: calendar, capacityBytes: nil
                    )
                    #expect(Set(samples).count == samples.count)
                    let widest = samples.map(\.count).max() ?? 0
                    // Every day of another year, at every hour of the day.
                    let start = moment.addingTimeInterval(-86_400 * 200)
                    var longest = 0
                    for day in 0..<366 {
                        for hour in stride(from: 0, to: 24, by: 5) {
                            let date = start.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600)
                            let shown = text(.date(date), widget, locale: locale).string
                            longest = max(longest, shown.count)
                        }
                    }
                    #expect(widest >= longest, "\(locale.identifier) \(preset) \(uses24HourClock)")
                }
            }
        }
    }

    @Test("The samples of durations, percents and byte counts cover their widest forms (D-12)")
    func otherSamples() {
        for source in [WidgetSource.uptime, .countdown] {
            for preset in source.presets {
                let widget = definition(source, preset: preset)
                let samples = WidgetFormat.widthSamples(for: widget, locale: english, calendar: calendar, capacityBytes: nil)
                let widest = samples.map(\.count).max() ?? 0
                var longest = 0
                // Up to 999 days, the widest uptime the samples cover.
                for minutes in stride(from: 0, through: 999 * 1440, by: 97) {
                    let duration = Duration.seconds(minutes * 60 + 59)
                    let reading: WidgetReading = source == .uptime
                        ? .duration(duration)
                        : .countdown(remaining: duration, isPassed: false)
                    longest = max(longest, text(reading, widget).string.count)
                }
                #expect(widest >= longest, "\(source) \(preset)")
                #expect(samples.contains { plain($0).contains("999") })
            }
        }
        let cpu = WidgetFormat.widthSamples(for: definition(.cpu), locale: english, calendar: calendar, capacityBytes: nil)
        #expect(cpu.map(plain) == ["100%"])
        let disk = WidgetFormat.widthSamples(
            for: definition(.freeDisk),
            locale: english,
            calendar: calendar,
            capacityBytes: 1_995_218_165_760
        )
        #expect(disk.map(plain).contains("9.9 GB"))
        #expect(disk.map(plain).contains("999.9 GB"))
        #expect(disk.map(plain).contains("2 TB"))
        let memory = WidgetFormat.widthSamples(
            for: definition(.memory, preset: .gigabytesUsed),
            locale: english,
            calendar: calendar,
            capacityBytes: 17_179_869_184
        )
        #expect(memory.map(plain).contains("16 GB"))
    }

    // MARK: Script widgets (D-12, D-23)

    private var script: WidgetDefinition {
        WidgetDefinition.script()
    }

    @Test("A script widget shows its line as given, never parsed (T-12-25)")
    func scriptLineIsShownAsGiven() {
        let lines = [
            "Up 3 d, 4 h",
            "100%",
            "<b>bold</b> <a href=\"https://example.org\">link</a>",
            "https://example.org/?a=1&b=2",
            "%@ %d \\(1) {time} ${HOME}",
            "\u{2013} \u{1F50B} 80",
        ]
        for line in lines {
            let result = text(.line(line), script)
            #expect(result.string == line)
            #expect(!result.isUnavailable)
            #expect(!result.isMuted)
            #expect(result.batteryState == nil)
        }
        // The same in every locale: the line is the script's, not formatted.
        #expect(text(.line("1,5 GB"), script, locale: german).string == "1,5 GB")
    }

    @Test("An empty line, an unavailable reading or a reading of another source is an en dash (D-13)")
    func scriptUnavailableIsEnDash() {
        for reading in [
            WidgetReading.line(""),
            .unavailable,
            .date(moment),
            .fraction(0.5),
            .bytes(10),
            .duration(.seconds(5)),
        ] {
            let result = text(reading, script)
            #expect(result.string == "\u{2013}")
            #expect(result.isUnavailable)
        }
    }

    @Test("A script widget has one fixed width sample of 8, 16 or 32 digits (D-12)")
    func scriptWidthSamples() {
        let expected: [(WidgetPreset, Int)] = [(.narrowText, 8), (.mediumText, 16), (.wideText, 32)]
        for (preset, count) in expected {
            var widget = script
            widget.preset = preset
            for locale in [english, swiss, german] {
                let samples = WidgetFormat.widthSamples(
                    for: widget, locale: locale, calendar: calendar, capacityBytes: 1_000_000
                )
                #expect(samples == [String(repeating: "0", count: count)])
            }
        }
        #expect(WidgetFormat.scriptWidthDigits(for: .narrowText) == 8)
        #expect(WidgetFormat.scriptWidthDigits(for: .mediumText) == 16)
        #expect(WidgetFormat.scriptWidthDigits(for: .wideText) == 32)
        // A format that is not a width falls back to the medium one.
        #expect(WidgetFormat.scriptWidthDigits(for: .percent) == 16)
    }
}
