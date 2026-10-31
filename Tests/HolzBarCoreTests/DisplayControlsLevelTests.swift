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

    @Test("A brightness never goes below the floor, so a slip cannot turn a display fully dark")
    func clampedBrightness() {
        #expect(Level.clampedBrightness(0.0) == 0.02)
        #expect(Level.clampedBrightness(1.3) == 1)
        #expect(Level.clampedBrightness(.nan) == 0.02)
        #expect(Level.clampedBrightness(0.5) == 0.5)
    }

    @Test("A step moves a level by whole steps of 5 percent, clamped and rounded to two decimals")
    func stepped() {
        #expect(Level.stepped(0.62, by: 1) == 0.67)
        #expect(Level.stepped(0.62, by: -1) == 0.57)
        #expect(Level.stepped(0.98, by: 1) == 1)
        #expect(Level.stepped(0.02, by: -1) == 0)
        #expect(Level.stepped(0.62, by: 3) == 0.77)
    }

    @Test("Repeated steps do not drift")
    func steppedDoesNotDrift() {
        var level = 0.0
        for _ in 0..<20 {
            level = Level.stepped(level, by: 1)
        }
        #expect(level == 1)
    }

    @Test("A read-back agrees with a request within 2 percent")
    func agrees() {
        #expect(Level.agrees(0.50, 0.51))
        #expect(!Level.agrees(0.50, 0.53))
        #expect(!Level.agrees(.nan, 0.5))
        #expect(!Level.agrees(0.5, .nan))
    }
}
