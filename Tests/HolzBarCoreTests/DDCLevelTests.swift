import Testing
@testable import HolzBarCore

@Suite("DDCLevel")
struct DDCLevelTests {
    typealias Level = DDCLevel

    @Test("A level is scaled to the maximum the monitor reports")
    func scales() {
        #expect(Level.raw(fromLevel: 0.5, maximum: 50, floor: Level.brightnessFloor) == 25)
        #expect(Level.raw(fromLevel: 1, maximum: 50, floor: Level.brightnessFloor) == 50)
        #expect(Level.raw(fromLevel: 0.49, maximum: 100, floor: 0) == 49)
    }

    @Test("A brightness never goes below the floor, and never to 0 on a coarse scale")
    func floorHolds() {
        #expect(Level.raw(fromLevel: 0.02, maximum: 50, floor: Level.brightnessFloor) == 1)
        #expect(Level.raw(fromLevel: 0, maximum: 50, floor: Level.brightnessFloor) == 1)
        #expect(Level.raw(fromLevel: 0.02, maximum: 3, floor: Level.brightnessFloor) == 1)
        #expect(Level.raw(fromLevel: -4, maximum: 100, floor: Level.brightnessFloor) == 2)
    }

    @Test("A level that is not a number or out of range is kept in range")
    func keptInRange() {
        #expect(Level.raw(fromLevel: .nan, maximum: 100, floor: 0) == 0)
        #expect(Level.raw(fromLevel: 7, maximum: 100, floor: 0) == 100)
        #expect(Level.raw(fromLevel: 0.5, maximum: 0, floor: Level.brightnessFloor) == 0)
    }

    @Test("A raw value becomes a level of at most 1, and no scale gives none")
    func levelFromRaw() {
        #expect(Level.level(raw: 15, maximum: 50) == 0.30)
        #expect(Level.level(raw: 49, maximum: 100) == 0.49)
        #expect(Level.level(raw: 60, maximum: 50) == 1)
        #expect(Level.level(raw: 5, maximum: 0) == nil)
    }
}
