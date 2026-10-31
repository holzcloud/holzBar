import Foundation
import Testing
@testable import HolzBarCore

@Suite("TimerInput")
struct TimerInputTests {
    @Test("Digits alone are minutes, and zero is refused")
    func minutes() {
        #expect(TimerInput.parseLength("25") == 1_500)
        #expect(TimerInput.parseLength("90") == 5_400)
        #expect(TimerInput.parseLength("1") == 60)
        #expect(TimerInput.parseLength("0") == nil)
        #expect(TimerInput.parseLength("00") == nil)
    }

    @Test("Colons give minutes and seconds, or hours, minutes and seconds, with seconds and minutes below 60")
    func clockForms() {
        #expect(TimerInput.parseLength("1:30") == 90)
        #expect(TimerInput.parseLength("0:45") == 45)
        #expect(TimerInput.parseLength("1:30:00") == 5_400)
        #expect(TimerInput.parseLength("99:59:59") == 359_999)
        #expect(TimerInput.parseLength("100:00:00") == nil)
        #expect(TimerInput.parseLength("1:75") == nil)
        #expect(TimerInput.parseLength("1:60:00") == nil)
        #expect(TimerInput.parseLength(":30") == nil)
        #expect(TimerInput.parseLength("1:") == nil)
        #expect(TimerInput.parseLength(":") == nil)
        #expect(TimerInput.parseLength("1:2:3:4") == nil)
        #expect(TimerInput.parseLength("0:00") == nil)
        #expect(TimerInput.parseLength("1 : 30") == nil)
    }

    @Test("Numbers with units are read in any order, with spaces, in capitals and with long names")
    func unitForms() {
        #expect(TimerInput.parseLength("1h") == 3_600)
        #expect(TimerInput.parseLength("1h30m") == 5_400)
        #expect(TimerInput.parseLength("2m 30s") == 150)
        #expect(TimerInput.parseLength("45 s") == 45)
        #expect(TimerInput.parseLength("5 min") == 300)
        #expect(TimerInput.parseLength("1 hour 5 minutes") == 3_900)
        #expect(TimerInput.parseLength(" 5 MIN ") == 300)
        #expect(TimerInput.parseLength("30s 2m") == 150)
        #expect(TimerInput.parseLength("2 hrs") == 7_200)
        #expect(TimerInput.parseLength("10 secs") == 10)
    }

    @Test("A unit twice, an unknown unit, decimals, negatives, words and empty text are refused")
    func refusals() {
        for text in ["1m1m", "1d", "1.5", "-5", "abc", "", "   ", "1h 30", "m", "1 2", "5 minutess", "1,5", "+5", "٣"] {
            #expect(TimerInput.parseLength(text) == nil, "\(text)")
        }
    }

    @Test("A very long or very large number is refused without trapping")
    func hugeNumbers() {
        #expect(TimerInput.parseLength("12345678901234567890") == nil)
        #expect(TimerInput.parseLength("1234567") == nil)
        #expect(TimerInput.parseLength("99999999999999999999h") == nil)
        #expect(TimerInput.parseLength("1234567m") == nil)
        #expect(TimerInput.parseLength(String(repeating: "9", count: 100_000)) == nil)
        #expect(TimerInput.parseLength(String(repeating: "1h", count: 50_000)) == nil)
    }

    @Test("A total above 99 hours 59 minutes 59 seconds is refused, and the limit itself is accepted")
    func totalLimit() {
        #expect(TimerInput.parseLength("99h 59m 60s") == nil)
        #expect(TimerInput.parseLength("99h 59m 59s") == 359_999)
        #expect(TimerInput.parseLength("100h") == nil)
        #expect(TimerInput.parseLength("5999m") == 359_940)
        #expect(TimerInput.parseLength("6000m") == nil)
    }

    @Test("The presets are 1, 5, 10 and 25 minutes and 1 hour, inside the board's limits")
    func presets() {
        #expect(TimerInput.presets == [60, 300, 600, 1_500, 3_600])
        for preset in TimerInput.presets {
            #expect(preset >= TimerBoard.minimumLength)
            #expect(preset <= TimerBoard.maximumLength)
        }
    }
}
