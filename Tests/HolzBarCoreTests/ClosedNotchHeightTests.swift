import Foundation
import Testing
@testable import HolzBarCore

@Suite("Closed notch height")
struct ClosedNotchHeightTests {
    @Test("A menu bar a little taller than the inset is the closed height")
    func measuredHeight() {
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 33) == 33)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 32) == 32)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 36) == 36)
    }

    @Test("The limit is 4 points above the inset and not a hundredth more")
    func limit() {
        #expect(ClosedNotchHeight.maximumDifference == 4)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 36.01) == 32)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 80) == 32)
    }

    @Test("A menu bar shorter than the inset, or none measured, gives the inset")
    func fallsBackToTheInset() {
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 38, menuBarHeight: 37) == 38)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: 0) == 32)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: -5) == 32)
    }

    @Test("A display without a notch gives 0")
    func noNotch() {
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 0, menuBarHeight: 24) == 0)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: -3, menuBarHeight: 24) == 0)
    }

    @Test("A number that is not finite never reaches the layout")
    func notANumber() {
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: .nan) == 32)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: 32, menuBarHeight: .infinity) == 32)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: .nan, menuBarHeight: 33) == 0)
        #expect(ClosedNotchHeight.resolve(safeAreaTop: .infinity, menuBarHeight: 33) == 0)
    }
}
