import Foundation
import Testing
@testable import HolzBarCore

@Suite("SoftwareDimming")
struct SoftwareDimmingTests {
    @Test("The floor is 90 percent and below 1")
    func floor() {
        #expect(SoftwareDimming.maximum == 0.9)
        #expect(SoftwareDimming.maximum < 1)
    }

    @Test("A level is held to 0 through the floor")
    func clamping() {
        #expect(SoftwareDimming.clamped(0.9) == 0.9)
        #expect(SoftwareDimming.clamped(0.95) == 0.9)
        #expect(SoftwareDimming.clamped(1) == 0.9)
        #expect(SoftwareDimming.clamped(0.45) == 0.45)
        #expect(SoftwareDimming.clamped(0) == 0)
        #expect(SoftwareDimming.clamped(-0.2) == 0)
        #expect(SoftwareDimming.clamped(.nan) == 0)
        #expect(SoftwareDimming.clamped(.infinity) == 0)
        #expect(SoftwareDimming.clamped(-.infinity) == 0)
    }

    @Test("The stored form keeps numbers only, clamped, and drops levels that clamp to 0")
    func cleaningValues() {
        let cleaned = SoftwareDimming.cleaned([
            "a": 0.5,
            "b": 2.0,
            "c": -1.0,
            "d": 0,
            "e": "0.5",
            "g": [0.5],
            "h": Double.nan,
        ])
        #expect(cleaned["a"] == 0.5)
        #expect(cleaned["b"] == 0.9)
        #expect(cleaned["c"] == nil)
        #expect(cleaned["d"] == nil)
        #expect(cleaned["e"] == nil)
        #expect(cleaned["g"] == nil)
        #expect(cleaned["h"] == nil)
    }

    @Test("An empty identifier or one longer than 64 bytes is dropped, one of 64 bytes stays")
    func cleaningIdentifiers() {
        let longest = String(repeating: "x", count: SoftwareDimming.maximumIdentifierLength)
        let tooLong = String(repeating: "x", count: SoftwareDimming.maximumIdentifierLength + 1)
        let cleaned = SoftwareDimming.cleaned(["": 0.5, longest: 0.5, tooLong: 0.5])
        #expect(cleaned.keys.sorted() == [longest])
        // The limit counts bytes, not characters.
        let wide = String(repeating: "é", count: 33)
        #expect(SoftwareDimming.cleaned([wide: 0.5]).isEmpty)
    }

    @Test("At most 32 entries are kept, the first 32 in sorted order")
    func cleaningCount() {
        var stored = [String: Any]()
        for index in 0..<40 {
            stored[String(format: "d%02d", index)] = 0.5
        }
        let cleaned = SoftwareDimming.cleaned(stored)
        #expect(cleaned.count == SoftwareDimming.maximumDisplays)
        #expect(cleaned.keys.sorted() == (0..<32).map { String(format: "d%02d", $0) })
        #expect(SoftwareDimming.cleaned([:]).isEmpty)
    }

    @Test("A layer exists only for a level above 0 with the hub on, the module on and the display present")
    func layer() {
        #expect(SoftwareDimming.layerExists(level: 0.5, hubOn: true, moduleOn: true, displayPresent: true))
        #expect(!SoftwareDimming.layerExists(level: 0, hubOn: true, moduleOn: true, displayPresent: true))
        #expect(!SoftwareDimming.layerExists(level: 0.5, hubOn: false, moduleOn: true, displayPresent: true))
        #expect(!SoftwareDimming.layerExists(level: 0.5, hubOn: true, moduleOn: false, displayPresent: true))
        #expect(!SoftwareDimming.layerExists(level: 0.5, hubOn: true, moduleOn: true, displayPresent: false))
    }

    @Test("Hardware control supersedes the layer exactly when the row is gone for that reason")
    func superseded() {
        // macOS can change the display: always superseded.
        for answer in [DimmingDDCAnswer.reading, .answersBrightness, .noBrightness] {
            #expect(SoftwareDimming.isSupersededByHardware(macOSCanChange: true, ddcSwitchOn: false, answer: answer))
            #expect(SoftwareDimming.isSupersededByHardware(macOSCanChange: true, ddcSwitchOn: true, answer: answer))
        }
        // DDC on and the monitor answers brightness: superseded.
        #expect(SoftwareDimming.isSupersededByHardware(macOSCanChange: false, ddcSwitchOn: true, answer: .answersBrightness))
        // Still being read, no brightness, or DDC off: the layer stays.
        #expect(!SoftwareDimming.isSupersededByHardware(macOSCanChange: false, ddcSwitchOn: true, answer: .reading))
        #expect(!SoftwareDimming.isSupersededByHardware(macOSCanChange: false, ddcSwitchOn: true, answer: .noBrightness))
        #expect(!SoftwareDimming.isSupersededByHardware(macOSCanChange: false, ddcSwitchOn: false, answer: .answersBrightness))
        #expect(!SoftwareDimming.isSupersededByHardware(macOSCanChange: false, ddcSwitchOn: false, answer: .noBrightness))
    }

    @Test("A superseded display never offers the dim row, so its cleared level leaves no layer without a control")
    func supersededMeansNoRow() {
        for macOS in [false, true] {
            for ddc in [false, true] {
                for answer in [DimmingDDCAnswer.reading, .answersBrightness, .noBrightness] {
                    if SoftwareDimming.isSupersededByHardware(macOSCanChange: macOS, ddcSwitchOn: ddc, answer: answer) {
                        #expect(!SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: macOS, ddcSwitchOn: ddc, answer: answer))
                    }
                }
            }
        }
    }

    @Test("The dim row shows for external displays macOS cannot change, by the DDC rule")
    func offer() {
        let answers: [DimmingDDCAnswer] = [.reading, .answersBrightness, .noBrightness]
        for answer in answers {
            // Not external, or macOS can change it: never.
            #expect(!SoftwareDimming.offersDimming(isExternal: false, macOSCanChange: false, ddcSwitchOn: false, answer: answer))
            #expect(!SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: true, ddcSwitchOn: false, answer: answer))
            // DDC off: always, whatever the answer.
            #expect(SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: false, ddcSwitchOn: false, answer: answer))
        }
        #expect(!SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: false, ddcSwitchOn: true, answer: .answersBrightness))
        #expect(SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: false, ddcSwitchOn: true, answer: .noBrightness))
        #expect(!SoftwareDimming.offersDimming(isExternal: true, macOSCanChange: false, ddcSwitchOn: true, answer: .reading))
    }
}
