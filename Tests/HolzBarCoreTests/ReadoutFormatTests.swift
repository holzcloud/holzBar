import Foundation
import Testing
@testable import HolzBarCore

@Suite("ReadoutFormat")
struct ReadoutFormatTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let texts = ReadoutTexts.english

    private func rate(_ value: Double?, unit: ReadoutRateUnit = .bytes, locale: Locale? = nil) -> String? {
        ReadoutFormat.rate(value, unit: unit, texts: texts, locale: locale ?? english)?.text
    }

    @Test("A rate is written in decimal units chosen by size, never in bytes")
    func rateUnitsAndDigits() {
        #expect(rate(0) == "0 kB/s")
        #expect(rate(99) == "0 kB/s")
        #expect(rate(100) == "0.1 kB/s")
        #expect(rate(85_000) == "85.0 kB/s")
        #expect(rate(999_400) == "999 kB/s")
        #expect(rate(1_200_000) == "1.2 MB/s")
        #expect(rate(99_940_000) == "99.9 MB/s")
        #expect(rate(123_000_000) == "123 MB/s")
        #expect(rate(1_240_000_000) == "1.2 GB/s")
        #expect(rate(250_000_000_000) == "250 GB/s")
    }

    @Test("A rounded 1000 moves to the next unit and a rounded 100 loses its fraction")
    func rateRounding() {
        #expect(rate(999_600) == "1.0 MB/s")
        #expect(rate(999_600_000) == "1.0 GB/s")
        #expect(rate(99_960) == "100 kB/s")
        #expect(rate(99_960_000) == "100 MB/s")
    }

    @Test("The number follows the locale")
    func rateLocale() {
        #expect(rate(1_200_000, locale: german) == "1,2 MB/s")
        #expect(rate(123_000_000, locale: german) == "123 MB/s")
    }

    @Test("Bits are eight times the bytes with their own symbols")
    func rateBits() {
        #expect(rate(1_200_000, unit: .bits) == "9.6 Mb/s")
        #expect(rate(0, unit: .bits) == "0 kb/s")
        #expect(rate(125_000_000, unit: .bits) == "1.0 Gb/s")
        #expect(rate(1_000, unit: .bits) == "8.0 kb/s")
    }

    @Test("The number and the unit come apart for a tile")
    func rateParts() {
        let parts = ReadoutFormat.rate(85_000, unit: .bytes, texts: texts, locale: english)
        #expect(parts == ReadoutRateText(number: "85.0", unit: "kB/s", text: "85.0 kB/s"))
    }

    @Test("A missing, negative or impossible rate has no text")
    func rateNothing() {
        #expect(rate(nil) == nil)
        #expect(rate(-1) == nil)
        #expect(rate(.nan) == nil)
        #expect(rate(.infinity) == nil)
        #expect(rate(-.infinity) == nil)
    }

    @Test("The width samples hold the widest text of every unit")
    func widthSamples() {
        let bytes = ReadoutFormat.rateWidthSamples(unit: .bytes, texts: texts, locale: english)
        #expect(bytes == ["99.9 kB/s", "999 kB/s", "99.9 MB/s", "999 MB/s", "99.9 GB/s", "999 GB/s"])
        let bits = ReadoutFormat.rateWidthSamples(unit: .bits, texts: texts, locale: english)
        #expect(bits == ["99.9 kb/s", "999 kb/s", "99.9 Mb/s", "999 Mb/s", "99.9 Gb/s", "999 Gb/s"])
        #expect(Set(bytes).count == bytes.count)
        let german = ReadoutFormat.rateWidthSamples(unit: .bytes, texts: texts, locale: german)
        #expect(german.first == "99,9 kB/s")
    }

    @Test("The unit symbols come from the texts")
    func symbolsFromTexts() {
        var french = texts
        french.byteSymbols = ["ko", "Mo", "Go"]
        french.perSecondFormat = "%@/s"
        let parts = ReadoutFormat.rate(1_200_000, unit: .bytes, texts: french, locale: Locale(identifier: "fr_FR"))
        #expect(parts?.text == "1,2 Mo/s")

        var broken = texts
        broken.byteSymbols = ["kB"]
        // A texts value with too few symbols gives no text and never traps.
        #expect(ReadoutFormat.rate(1_200_000, unit: .bytes, texts: broken, locale: english) == nil)
        #expect(ReadoutFormat.rate(1_200, unit: .bytes, texts: broken, locale: english)?.text == "1.2 kB/s")
    }

    @Test("The words of the English texts")
    func words() {
        #expect(ReadoutFormat.pressureWord(.normal, texts: texts) == "Normal")
        #expect(ReadoutFormat.pressureWord(.warning, texts: texts) == "High")
        #expect(ReadoutFormat.pressureWord(.critical, texts: texts) == "Critical")
        #expect(ReadoutFormat.thermalWord(.nominal, texts: texts) == "Nominal")
        #expect(ReadoutFormat.thermalWord(.fair, texts: texts) == "Fair")
        #expect(ReadoutFormat.thermalWord(.serious, texts: texts) == "Serious")
        #expect(ReadoutFormat.thermalWord(.critical, texts: texts) == "Critical")
        #expect(texts.fill(texts.readFormat, with: "1.2 MB/s") == "R 1.2 MB/s")
        #expect(texts.fill(texts.writeFormat, with: "85.0 kB/s") == "W 85.0 kB/s")
        #expect(texts.fill(texts.wattsFormat, with: "96") == "96 W")
        #expect(texts.clusterText(.performance, value: "42%") == "P 42%")
        #expect(texts.clusterText(.efficiency, value: "12%") == "E 12%")
        #expect(texts.clusterText(.other("S"), value: "7%") == "S 7%")
        #expect(texts.clusterLabels.isEmpty)
    }

    @Test("The stored unit raw values never change")
    func unitRawValues() {
        #expect(ReadoutRateUnit.bytes.rawValue == 0)
        #expect(ReadoutRateUnit.bits.rawValue == 1)
        #expect(ReadoutRateUnit.allCases.count == 2)
    }
}
