import Testing
@testable import HolzBarCore

@Suite("DisplayControlsLevel")
struct DisplayControlsLevelTests {
    typealias Level = DisplayControlsLevel

    @Test("A level is kept between 0 and 1, and a value that is not a number becomes 0")
    func clamped() {
        #expect(Level.clamped(-0.2) == 0)
        #expect(Level.clamped(1.4) == 1)
        #expect(Level.clamped(0.4) == 0.4)
        #expect(Level.clamped(.nan) == 0)
        #expect(Level.clamped(.infinity) == 0)
    }

    @Test("The percent is the whole percent, rounded")
    func percent() {
        #expect(Level.percent(0.62) == 62)
        #expect(Level.percent(0.625) == 63)
        #expect(Level.percent(0) == 0)
        #expect(Level.percent(2) == 100)
    }
}
