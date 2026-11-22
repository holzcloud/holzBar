//
//  ReadoutTileBuilder.swift
//  holzBar
//

import Foundation
import SwiftUI

/// Turns the pure contents of the System readouts tiles (``ReadoutTiles``) into the hub's tiles:
/// the name, the value and its unit, the symbol, the one quiet line or state line, and the
/// spoken value that is also the tooltip. Core decides what a tile shows; this writes it in the
/// user's language. Nothing here reads the system and nothing is logged.
enum ReadoutTileBuilder {
    /// The value of a tile that has none: an en dash, with no unit (R4).
    static let unavailableValue = "\u{2013}"

    /// The tile for a content.
    ///
    /// - Parameters:
    ///   - content: What the tile shows.
    ///   - input: The readings behind it, for the amounts the spoken value names.
    ///   - rateUnit: How the network speed counts.
    ///   - locale: The language and the number format of the user.
    ///   - history: The tile's mini curve, for a tile that has one.
    ///   - summary: What the last two minutes did, which VoiceOver reads after the value (the
    ///     tooltip does not have it).
    static func tile(
        for content: ReadoutTileContent,
        input: ReadoutTileInput,
        rateUnit: ReadoutRateUnit,
        locale: Locale,
        history: HubTileHistory? = nil,
        summary: ReadoutHistorySummary? = nil
    ) -> HubTile {
        let texts = ReadoutTexts.localized(locale: locale)
        let (value, unit) = valueAndUnit(of: content.value, rateUnit: rateUnit, texts: texts, locale: locale)
        let reading = spokenValue(for: content, input: input, rateUnit: rateUnit, texts: texts, locale: locale)
        let spoken = Text(verbatim: reading)
        let withSummary = summary.map {
            Text(verbatim: reading + ", " + historyPhrase($0, kind: content.kind, rateUnit: rateUnit, locale: locale))
        } ?? spoken
        let parts = detail(of: content.detail, kind: content.kind, rateUnit: rateUnit, texts: texts, locale: locale)
        return HubTile(
            symbol: symbol(for: content, input: input),
            title: title(of: content.kind),
            value: value,
            unit: unit,
            detail: parts.detail,
            fraction: content.fraction,
            key: content.kind.rawValue,
            level: content.level,
            stateLine: parts.stateLine,
            accessibilityValue: withSummary,
            help: spoken,
            history: history
        )
    }

    // MARK: Names and symbols

    private static func title(of kind: ReadoutTileKind) -> Text {
        switch kind {
        case .cpu: Text("CPU")
        case .gpu: Text("GPU")
        case .memory: Text("Memory")
        case .network: Text("Network")
        case .disk: Text("Disk")
        case .battery: Text("Battery")
        }
    }

    private static func symbol(for content: ReadoutTileContent, input: ReadoutTileInput) -> String {
        switch content.kind {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: batterySymbol(percent: input.power?.percent, isCharging: input.power?.state == .charging)
        }
    }

    /// The battery symbol nearest to the charge: 0, 25, 50, 75 or 100 percent, with a bolt while it
    /// charges.
    static func batterySymbol(percent: Int?, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        let steps = [0, 25, 50, 75, 100]
        let level = min(max(percent ?? 0, 0), 100)
        let nearest = steps.min { abs($0 - level) < abs($1 - level) } ?? 0
        return "battery.\(nearest)percent"
    }

    // MARK: Value and unit

    private static func valueAndUnit(
        of value: ReadoutTileValue,
        rateUnit: ReadoutRateUnit,
        texts: ReadoutTexts,
        locale: Locale
    ) -> (String, Text?) {
        switch value {
        case .percent(let percent):
            return (percent.formatted(.number.grouping(.never).locale(locale)), Text(verbatim: "%"))
        case .rate(let rate):
            guard let text = ReadoutFormat.rate(rate, unit: rateUnit, texts: texts, locale: locale) else {
                return (unavailableValue, nil)
            }
            return (text.number, Text(verbatim: text.unit))
        case .bytes(let bytes):
            return split(amount(bytes, style: .file, locale: locale))
        case .unavailable:
            return (unavailableValue, nil)
        }
    }

    /// An amount of bytes as the system writes it in the locale (such as "212 GB"), counted as
    /// memory (binary units) or as files (decimal units).
    private static func amount(_ bytes: Int64, style: ByteCountFormatStyle.Style, locale: Locale) -> String {
        bytes.formatted(ByteCountFormatStyle(style: style, locale: locale))
    }

    /// Splits a number from its unit at the last space, so the tile can set them in two sizes. A
    /// text without a space stays whole.
    private static func split(_ text: String) -> (String, Text?) {
        guard let space = text.lastIndex(where: \.isWhitespace) else {
            return (text, nil)
        }
        let unit = text[text.index(after: space)...]
        return (String(text[..<space]), unit.isEmpty ? nil : Text(verbatim: String(unit)))
    }

    // MARK: Detail

    private static func detail(
        of detail: ReadoutTileDetail?,
        kind: ReadoutTileKind,
        rateUnit: ReadoutRateUnit,
        texts: ReadoutTexts,
        locale: Locale
    ) -> (detail: Text?, stateLine: HubTileStateLine?) {
        guard let detail else {
            return (nil, nil)
        }
        switch detail {
        case .thermal(let state):
            return (nil, thermalLine(state, texts: texts))
        case .pressure(let pressure):
            return (nil, pressureLine(pressure))
        case .clusters(let clusters):
            return (Text(verbatim: clusterText(clusters, texts: texts, locale: locale)), nil)
        case .swap(let bytes):
            let amount = amount(bytes, style: .memory, locale: locale)
            return (Text("Swap \(amount)"), nil)
        case .capacity(let bytes):
            let amount = amount(bytes, style: kind == .memory ? .memory : .file, locale: locale)
            return (Text("of \(amount)"), nil)
        case .upload(let rate):
            guard let text = ReadoutFormat.rate(rate, unit: rateUnit, texts: texts, locale: locale) else {
                return (nil, nil)
            }
            return (Text(verbatim: "\u{2191}" + text.text), nil)
        case .timeLeft(let time):
            let amount = durationText(time, locale: locale)
            return (Text("\(amount) left"), nil)
        case .timeToFull(let time):
            let amount = durationText(time, locale: locale)
            return (Text("\(amount) to full"), nil)
        case .onBattery:
            return (Text("On battery"), nil)
        case .charging:
            return (Text("Charging"), nil)
        case .charged:
            return (Text("Charged"), nil)
        case .onAdapter:
            return (Text("On power adapter"), nil)
        case .adapterWatts(let watts):
            let amount = texts.fill(texts.wattsFormat, with: watts.formatted(.number.locale(locale)))
            return (Text("\(amount) adapter"), nil)
        case .notAvailable:
            return (Text("Not available"), nil)
        }
    }

    /// The thermal state as a symbol and a word in the state's colour: Fair neutral, Serious
    /// amber, Critical red. Nominal has no line.
    private static func thermalLine(_ state: ReadoutThermal, texts: ReadoutTexts) -> HubTileStateLine? {
        let word = Text(verbatim: ReadoutFormat.thermalWord(state, texts: texts))
        switch state {
        case .nominal: return nil
        case .fair: return HubTileStateLine(symbol: "thermometer.medium", text: word, tint: .neutral)
        case .serious: return HubTileStateLine(symbol: "thermometer.high", text: word, tint: .amber)
        case .critical: return HubTileStateLine(symbol: "thermometer.high", text: word, tint: .red)
        }
    }

    /// The memory pressure as a symbol and a phrase while it is not normal: High amber, Critical
    /// red.
    private static func pressureLine(_ pressure: ReadoutPressure) -> HubTileStateLine? {
        switch pressure {
        case .normal: nil
        case .warning: HubTileStateLine(symbol: "exclamationmark.triangle", text: Text("Pressure high"), tint: .amber)
        case .critical: HubTileStateLine(symbol: "exclamationmark.triangle", text: Text("Pressure critical"), tint: .red)
        }
    }

    /// The load of every cluster: "P 42 % \u{00B7} E 12 %".
    private static func clusterText(_ clusters: [ClusterLoad], texts: ReadoutTexts, locale: Locale) -> String {
        clusters.map { cluster in
            let letter = switch cluster.label {
            case .performance: texts.performanceLetter
            case .efficiency: texts.efficiencyLetter
            case .other(let name): name
            }
            let percent = ReadoutTiles.percent(cluster.load).formatted(.number.grouping(.never).locale(locale))
            return "\(letter) \(percent) %"
        }
        .joined(separator: " \u{00B7} ")
    }

    /// A time as hours and minutes, abbreviated, such as "2 hr 10 min".
    private static func durationText(_ time: Duration, locale: Locale) -> String {
        time.formatted(
            Duration.UnitsFormatStyle(
                allowedUnits: [.days, .hours, .minutes],
                width: .abbreviated,
                maximumUnitCount: 2,
                fractionalPart: .hide(rounded: .down)
            ).locale(locale)
        )
    }

    // MARK: Spoken value

    /// The value in words, which is the tile's VoiceOver value and its tooltip: the reading, then
    /// the extras, joined by commas. The thermal state is in it while the thermal switch is on,
    /// Nominal included.
    private static func spokenValue(
        for content: ReadoutTileContent,
        input: ReadoutTileInput,
        rateUnit: ReadoutRateUnit,
        texts: ReadoutTexts,
        locale: Locale
    ) -> String {
        var parts = [String]()
        switch content.kind {
        case .cpu, .gpu:
            parts.append(percentPhrase(content.value))
        case .memory:
            parts += memoryPhrases(content, input: input, texts: texts, locale: locale)
        case .network:
            parts.append(networkPhrase(content, rateUnit: rateUnit, locale: locale))
        case .disk:
            parts.append(diskPhrase(content, input: input, locale: locale))
        case .battery:
            parts += batteryPhrases(content, input: input, locale: locale)
        }
        if let state = content.spokenThermal {
            parts.append(String(localized: "Thermal state \(ReadoutFormat.thermalWord(state, texts: texts))"))
        }
        return parts.joined(separator: ", ")
    }

    /// What the last two minutes did, in words: "Last 2 minutes: 8 percent to 41 percent, rising".
    /// The lowest and the highest are percents for a share and speeds for the network.
    private static func historyPhrase(
        _ summary: ReadoutHistorySummary,
        kind: ReadoutTileKind,
        rateUnit: ReadoutRateUnit,
        locale: Locale
    ) -> String {
        let lowest: String
        let highest: String
        if kind == .network {
            lowest = WidgetSpeech.spokenRate(summary.lowest, unit: rateUnit, locale: locale)
            highest = WidgetSpeech.spokenRate(summary.highest, unit: rateUnit, locale: locale)
        } else {
            let low = ReadoutTiles.percent(summary.lowest)
            let high = ReadoutTiles.percent(summary.highest)
            lowest = String(localized: "\(low) percent")
            highest = String(localized: "\(high) percent")
        }
        let format = switch summary.trend {
        case .rising: String(localized: "Last 2 minutes: %1$@ to %2$@, rising")
        case .falling: String(localized: "Last 2 minutes: %1$@ to %2$@, falling")
        case .steady: String(localized: "Last 2 minutes: %1$@ to %2$@, steady")
        }
        return String(format: format, lowest, highest)
    }

    private static func percentPhrase(_ value: ReadoutTileValue) -> String {
        guard case .percent(let percent) = value else {
            return String(localized: "unavailable")
        }
        return String(localized: "\(percent) percent")
    }

    private static func memoryPhrases(
        _ content: ReadoutTileContent,
        input: ReadoutTileInput,
        texts: ReadoutTexts,
        locale: Locale
    ) -> [String] {
        guard let memory = input.memory, content.value != .unavailable else {
            return [String(localized: "unavailable")]
        }
        let gibibyte = 1_073_741_824.0
        let used = WidgetSpeech.gigabytes(memory.used, perGigabyte: gibibyte, locale: locale)
        let total = WidgetSpeech.gigabytes(memory.total, perGigabyte: gibibyte, locale: locale)
        var phrases = [String(localized: "\(used) used of \(total)")]
        if let pressure = input.pressure {
            phrases.append(String(localized: "Memory pressure \(ReadoutFormat.pressureWord(pressure, texts: texts))"))
        }
        if let swap = input.swap, swap.used > 0 {
            phrases.append(String(localized: "Swap \(WidgetSpeech.gigabytes(swap.used, perGigabyte: gibibyte, locale: locale))"))
        }
        return phrases
    }

    private static func networkPhrase(_ content: ReadoutTileContent, rateUnit: ReadoutRateUnit, locale: Locale) -> String {
        guard case .rate(let rate) = content.value, case .upload(let upRate) = content.detail else {
            return String(localized: "unavailable")
        }
        let download = WidgetSpeech.spokenRate(rate, unit: rateUnit, locale: locale)
        let upload = WidgetSpeech.spokenRate(upRate, unit: rateUnit, locale: locale)
        return String(localized: "Download \(download), upload \(upload)")
    }

    private static func diskPhrase(_ content: ReadoutTileContent, input: ReadoutTileInput, locale: Locale) -> String {
        guard case .bytes(let free) = content.value, let total = input.diskSpace?.total else {
            return String(localized: "unavailable")
        }
        let decimal = 1_000_000_000.0
        let freeText = WidgetSpeech.gigabytes(UInt64(max(free, 0)), perGigabyte: decimal, locale: locale)
        let totalText = WidgetSpeech.gigabytes(UInt64(max(total, 0)), perGigabyte: decimal, locale: locale)
        return String(localized: "\(freeText) free of \(totalText)")
    }

    private static func batteryPhrases(_ content: ReadoutTileContent, input: ReadoutTileInput, locale: Locale) -> [String] {
        guard content.value != .unavailable, let power = input.power else {
            return [String(localized: "unavailable")]
        }
        let reading = WidgetReading.power(power)
        var phrases = [WidgetSpeech.batteryValue(for: reading, preset: .percentAndTimeLeft, locale: locale)]
        phrases.append(WidgetSpeech.batteryValue(for: reading, preset: .adapterWatts, locale: locale))
        return phrases.compactMap { $0 }
    }
}
