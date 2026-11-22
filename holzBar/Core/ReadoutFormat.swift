//
//  ReadoutFormat.swift
//  holzBar
//

import Foundation

/// How a rate is counted: bytes per second or bits per second (D-08). The raw values are stored
/// in the settings; new cases are appended and the existing ones never change.
nonisolated enum ReadoutRateUnit: Int, CaseIterable, Sendable {
    case bytes = 0
    case bits = 1
}

/// The words and unit symbols the readout texts are made of, in the user's language.
///
/// Core makes the numbers and chooses the units; the app builds these texts from its string
/// catalog and from the system's abbreviations in the user's locale (94-03), so Core stays
/// testable without a catalog.
nonisolated struct ReadoutTexts: Equatable, Sendable {
    /// The symbols of kilo, mega and giga bytes.
    var byteSymbols: [String]
    /// The symbols of kilo, mega and giga bits.
    var bitSymbols: [String]
    /// The per-second form of a unit symbol; one `%@`.
    var perSecondFormat: String
    var pressureNormal: String
    var pressureHigh: String
    var pressureCritical: String
    var thermalNominal: String
    var thermalFair: String
    var thermalSerious: String
    var thermalCritical: String
    /// The letter of the performance cores in the cluster text.
    var performanceLetter: String
    /// The letter of the efficiency cores in the cluster text.
    var efficiencyLetter: String
    /// The label of a disk read rate; one `%@`.
    var readFormat: String
    /// The label of a disk write rate; one `%@`.
    var writeFormat: String
    /// A power in watts; one `%@`.
    var wattsFormat: String

    /// The English texts, which the tests use.
    static let english = ReadoutTexts(
        byteSymbols: ["kB", "MB", "GB"],
        bitSymbols: ["kb", "Mb", "Gb"],
        perSecondFormat: "%@/s",
        pressureNormal: "Normal",
        pressureHigh: "High",
        pressureCritical: "Critical",
        thermalNominal: "Nominal",
        thermalFair: "Fair",
        thermalSerious: "Serious",
        thermalCritical: "Critical",
        performanceLetter: "P",
        efficiencyLetter: "E",
        readFormat: "R %@",
        writeFormat: "W %@",
        wattsFormat: "%@ W"
    )

    /// A text with its one `%@` replaced.
    func fill(_ format: String, with value: String) -> String {
        format.replacingOccurrences(of: "%@", with: value)
    }
}

/// A rate as text: the number and its unit apart, for a tile that sets them in two sizes, and
/// together for the menu bar.
nonisolated struct ReadoutRateText: Equatable, Sendable {
    /// The number in the user's locale, such as `85.0`.
    var number: String
    /// The unit with the per-second suffix, such as `kB/s`.
    var unit: String
    /// The number, a space and the unit.
    var text: String
}

/// The text of the system readouts (D-08, UI contract "Rates").
nonisolated enum ReadoutFormat {
    /// The largest number that is shown with its unit before it moves to the next (a rounded 1000
    /// is written in the next unit).
    private static let unitLimit = 999.5
    /// The largest number that is shown with a fraction digit: from 99.95 on it rounds to 100,
    /// which is written without one.
    private static let fractionLimit = 99.95
    /// Below this number of kilobytes a rate is written as zero.
    private static let zeroLimit = 0.1

    /// The rate as text, in decimal units chosen by size and never in bytes: kB below 1 MB, MB
    /// below 1 GB and GB above (bits: kb, Mb, Gb). One fraction digit below 100, none from 100 to
    /// 999, in the user's locale; below 0.1 kB/s the text is `0 kB/s`.
    ///
    /// - Returns: `nil` for a missing, negative or not finite rate (the text then shows an en
    ///   dash).
    static func rate(
        _ bytesPerSecond: Double?,
        unit: ReadoutRateUnit,
        texts: ReadoutTexts,
        locale: Locale
    ) -> ReadoutRateText? {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else {
            return nil
        }
        let value = unit == .bits ? bytesPerSecond * 8 : bytesPerSecond
        var scaled = value / 1_000
        var index = 0
        while scaled >= unitLimit, index < 2 {
            scaled /= 1_000
            index += 1
        }
        return text(scaled: scaled, index: index, unit: unit, texts: texts, locale: locale)
    }

    /// The texts a rate readout can take at most in each unit (99.9 and 999 in kilo, mega and
    /// giga), so the status item can keep one width (D-11).
    static func rateWidthSamples(unit: ReadoutRateUnit, texts: ReadoutTexts, locale: Locale) -> [String] {
        var samples = [String]()
        for index in 0...2 {
            for scaled in [99.9, 999.0] {
                let sample = text(scaled: scaled, index: index, unit: unit, texts: texts, locale: locale)
                if let sample, !samples.contains(sample.text) {
                    samples.append(sample.text)
                }
            }
        }
        return samples
    }

    /// The word for a memory pressure level.
    static func pressureWord(_ pressure: ReadoutPressure, texts: ReadoutTexts) -> String {
        switch pressure {
        case .normal: texts.pressureNormal
        case .warning: texts.pressureHigh
        case .critical: texts.pressureCritical
        }
    }

    /// The word for a thermal state.
    static func thermalWord(_ thermal: ReadoutThermal, texts: ReadoutTexts) -> String {
        switch thermal {
        case .nominal: texts.thermalNominal
        case .fair: texts.thermalFair
        case .serious: texts.thermalSerious
        case .critical: texts.thermalCritical
        }
    }

    // MARK: Writing

    private static func text(
        scaled: Double,
        index: Int,
        unit: ReadoutRateUnit,
        texts: ReadoutTexts,
        locale: Locale
    ) -> ReadoutRateText? {
        let symbols = unit == .bits ? texts.bitSymbols : texts.byteSymbols
        guard symbols.indices.contains(index) else {
            return nil
        }
        let number: String
        if index == 0, scaled < zeroLimit {
            number = numberText(0, fractionDigits: 0, locale: locale)
        } else if scaled < fractionLimit {
            number = numberText(scaled, fractionDigits: 1, locale: locale)
        } else {
            number = numberText(scaled, fractionDigits: 0, locale: locale)
        }
        let unitText = texts.fill(texts.perSecondFormat, with: symbols[index])
        return ReadoutRateText(number: number, unit: unitText, text: number + " " + unitText)
    }

    private static func numberText(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .grouping(.never)
                .locale(locale)
        )
    }
}
