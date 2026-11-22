import Foundation
import Testing
@testable import HolzBarCore

@Suite("Display cutout")
struct DisplayCutoutTests {
    @Test("This Mac's measured notch (185 by 32 on 1512 points) is a notch")
    func measuredNotch() {
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: 32) == .notch)
        #expect(DisplayCutout.classify(displayWidth: 1470, leftAreaWidth: 642, rightAreaWidth: 642, safeAreaTop: 37) == .notch)
    }

    @Test("The cited island (about 59 by 40) is an island")
    func citedIsland() {
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 726.5, rightAreaWidth: 726.5, safeAreaTop: 40) == .island)
    }

    @Test("The limit is strict: a cutout exactly 3 times the safe top is a notch")
    func limitIsStrict() {
        #expect(DisplayCutout.islandRatioLimit == 3)
        // 120 / 40 == 3 exactly: a notch.
        #expect(DisplayCutout.classify(displayWidth: 1000, leftAreaWidth: 440, rightAreaWidth: 440, safeAreaTop: 40) == .notch)
        // 119 / 40 is below 3: an island.
        #expect(DisplayCutout.classify(displayWidth: 1000, leftAreaWidth: 440.5, rightAreaWidth: 440.5, safeAreaTop: 40) == .island)
        #expect(DisplayCutout.classify(displayWidth: 1000, leftAreaWidth: 440, rightAreaWidth: 440, safeAreaTop: 20) == .notch)
    }

    @Test("No safe area, a missing area or a display without width is none")
    func noCutout() {
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: 0) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: -4) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: nil, rightAreaWidth: 663.5, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: nil, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 0, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: -1, leftAreaWidth: 1, rightAreaWidth: 1, safeAreaTop: 32) == .none)
        // The areas cover the whole width: no cutout between them.
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 756, rightAreaWidth: 756, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 900, rightAreaWidth: 900, safeAreaTop: 32) == .none)
    }

    @Test("Values that are not numbers are none")
    func notNumbers() {
        let nan = Double.nan
        let inf = Double.infinity
        #expect(DisplayCutout.classify(displayWidth: nan, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: inf, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: nan, rightAreaWidth: 663.5, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: inf, safeAreaTop: 32) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: nan) == .none)
        #expect(DisplayCutout.classify(displayWidth: 1512, leftAreaWidth: 663.5, rightAreaWidth: 663.5, safeAreaTop: inf) == .none)
    }

    @Test("The raw values are stable, so they can be stored")
    func rawValues() {
        #expect(DisplayCutout.none.rawValue == 0)
        #expect(DisplayCutout.notch.rawValue == 1)
        #expect(DisplayCutout.island.rawValue == 2)
        #expect(DisplayCutout.allCases.count == 3)
    }
}
