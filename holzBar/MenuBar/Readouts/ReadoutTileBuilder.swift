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
    static func tile(
        for content: ReadoutTileContent,
        input: ReadoutTileInput,
        rateUnit: ReadoutRateUnit,
        locale: Locale
    ) -> HubTile {
        let texts = ReadoutTexts.localized(locale: locale)
        let (value, unit) = valueAndUnit(of: content.value, rateUnit: rateUnit, texts: texts, locale: locale)
        let spoken = Text(verbatim: spokenValue(for: content, input: input, rateUnit: rateUnit, texts: texts, locale: locale))
        let parts = detail(of: content.detail, texts: texts, locale: locale)
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
            accessibilityValue: spoken,
            help: spoken
        )
    }

    // MARK: Names and symbols

    private static func title(of kind: ReadoutTileKind) -> Text {
        switch kind {
        case .cpu: Text("CPU")
        case .gpu, .memory, .network, .disk, .battery: Text(verbatim: kind.rawValue)
        }
    }

    private static func symbol(for content: ReadoutTileContent, input: ReadoutTileInput) -> String {
        switch content.kind {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.0percent"
        }
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
            (percent.formatted(.number.grouping(.never).locale(locale)), Text(verbatim: "%"))
        case .rate, .bytes:
            (unavailableValue, nil)
        case .unavailable:
            (unavailableValue, nil)
        }
    }

    // MARK: Detail

    private static func detail(
        of detail: ReadoutTileDetail?,
        texts: ReadoutTexts,
        locale: Locale
    ) -> (detail: Text?, stateLine: HubTileStateLine?) {
        switch detail {
        case .thermal(let state):
            (nil, thermalLine(state, texts: texts))
        default:
            (nil, nil)
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
        switch content.value {
        case .percent(let percent):
            parts.append(String(localized: "\(percent) percent"))
        case .rate, .bytes, .unavailable:
            parts.append(String(localized: "unavailable"))
        }
        if let state = content.spokenThermal {
            parts.append(String(localized: "Thermal state \(ReadoutFormat.thermalWord(state, texts: texts))"))
        }
        return parts.joined(separator: ", ")
    }
}
