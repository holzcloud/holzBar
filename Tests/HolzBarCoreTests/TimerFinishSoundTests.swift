import Testing
@testable import HolzBarCore

@Suite("TimerFinishSound")
struct TimerFinishSoundTests {
    @Test("The raw values are stored and never change: none 0, Glass 1, Hero 2, Ping 3, Submarine 4, Tink 5")
    func rawValues() {
        #expect(TimerFinishSound.none.rawValue == 0)
        #expect(TimerFinishSound.glass.rawValue == 1)
        #expect(TimerFinishSound.hero.rawValue == 2)
        #expect(TimerFinishSound.ping.rawValue == 3)
        #expect(TimerFinishSound.submarine.rawValue == 4)
        #expect(TimerFinishSound.tink.rawValue == 5)
        #expect(TimerFinishSound.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
    }

    @Test("The system name is nil for none and the capitalised sound name for the others")
    func systemNames() {
        #expect(TimerFinishSound.none.systemName == nil)
        #expect(TimerFinishSound.allCases.dropFirst().compactMap(\.systemName) == ["Glass", "Hero", "Ping", "Submarine", "Tink"])
    }

    @Test("An unknown stored number reads as Glass and a valid one as itself")
    func storedValues() {
        for raw in [6, -1, 99, Int.max, Int.min] {
            #expect(TimerFinishSound.stored(raw) == .glass)
        }
        for sound in TimerFinishSound.allCases {
            #expect(TimerFinishSound.stored(sound.rawValue) == sound)
        }
    }
}
