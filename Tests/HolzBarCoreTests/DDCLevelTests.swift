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

    @Test("The contrast has the same 2 percent floor as the brightness, volume and mute have none")
    func floors() {
        #expect(Level.contrastFloor == 0.02)
        #expect(Level.floor(for: .brightness) == Level.brightnessFloor)
        #expect(Level.floor(for: .contrast) == 0.02)
        #expect(Level.floor(for: .volume) == 0)
        #expect(Level.floor(for: .mute) == 0)
        #expect(Level.raw(fromLevel: 0, maximum: 50, floor: Level.contrastFloor) == 1)
        #expect(Level.raw(fromLevel: 0, maximum: 100, floor: Level.floor(for: .volume)) == 0)
    }

    @Test("Only the raw value 1 means muted; 0 is what a never muted monitor may report")
    func muteReading() {
        #expect(Level.isMuted(raw: 1))
        #expect(!Level.isMuted(raw: 0))
        #expect(!Level.isMuted(raw: 2))
        #expect(!Level.isMuted(raw: 255))
    }

    @Test("Mute writes 1 and unmute writes 2")
    func muteWriting() {
        #expect(Level.muteRaw(true) == 1)
        #expect(Level.muteRaw(false) == 2)
    }
}
