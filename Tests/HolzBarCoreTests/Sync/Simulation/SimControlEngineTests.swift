import Foundation
import Testing

/// The oracles must see failures (D-11): each control engine is run over a bounded number of seeds and must be
/// caught. A control engine that survives means the generator or the oracles are too weak.
@Suite("SimControlEngines")
struct SimControlEngineTests {
    static let hour: Int64 = 3600 * 1000
    static let units = ["ShowOnHover", "UseIceBar", "RehideInterval", "Hotkeys/toggle"]

    /// Two redesigned Macs with different clock offsets, both running.
    static func twoMacs() -> [SimMacSpec] {
        [
            SimMacSpec(.A, .redesign, running: true),
            SimMacSpec(.B, .redesign, running: true, clockOffsetMilliseconds: 3 * hour),
        ]
    }

    /// A short random trace over two Macs, drawn from one seeded stream.
    static func events(seed: UInt64, macs: [SimMacName] = [.A, .B], count: Int = 40) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("control-events")
        var events: [SimEvent] = []
        for _ in 0..<count {
            let mac = random.pick(macs)
            switch random.int(in: 0...9) {
            case 0, 1, 2: events.append(.userEdit(mac: mac, unit: random.pick(units)))
            case 3: events.append(.userDelete(mac: mac, unit: random.pick(units)))
            case 4: events.append(.restartApp(mac: mac))
            case 5: events.append(.clockStep(mac: mac, milliseconds: Int64(random.int(in: -3...3)) * hour))
            case 6: events.append(.autoPlace(mac: mac, unit: random.pick(units)))
            default: events.append(.advance(milliseconds: Int64(random.int(in: 1...20)) * 1000))
            }
        }
        return events
    }

    static func run(
        seed: UInt64,
        events: [SimEvent],
        macs: [SimMacSpec] = twoMacs(),
        preset: SimProviderPreset? = .iCloud,
        factory: @escaping SimWorld.BrainFactory,
        oracles: SimOracleSet = .safety
    ) -> SimWorld {
        let world = SimWorld(seed: seed, macs: macs, preset: preset, brainFactory: factory, oracles: oracles)
        world.run(events)
        return world
    }

    static var lastWriterFactory: SimWorld.BrainFactory { { _, _ in LastWriterWinsByClock() } }

    @Test("The last-writer-wins-by-clock engine is caught by INV-S1, shrunk and printed")
    func lastWriterWinsIsCaughtShrunkAndPrinted() throws {
        var found: (seed: UInt64, events: [SimEvent], violation: SimViolation)?
        for seed in UInt64(1)...200 {
            let events = Self.events(seed: seed)
            let world = Self.run(seed: seed, events: events, factory: Self.lastWriterFactory)
            if let violation = world.oracleViolations.first(where: { $0.id == "INV-S1" }) {
                found = (seed, events, violation)
                break
            }
        }
        let failure = try #require(found, "LastWriterWinsByClock survived seeds 1 through 200")

        func failsWithS1(_ candidate: [SimEvent]) -> Bool {
            let world = Self.run(seed: failure.seed, events: candidate, factory: Self.lastWriterFactory)
            return world.oracleViolations.contains { $0.id == "INV-S1" }
        }
        let shrunk = SimShrinker().shrink(failure.events, failing: failsWithS1)
        #expect(failsWithS1(shrunk), "the shrunk trace must still fail")
        #expect(shrunk.count <= 12, "shrunk to \(shrunk.count) events")
        #expect(shrunk.count < failure.events.count)

        let world = Self.run(seed: failure.seed, events: shrunk, factory: Self.lastWriterFactory)
        let violation = try #require(world.oracleViolations.first { $0.id == "INV-S1" })
        let scenario = SimFailure(
            name: "last writer wins by clock", seed: failure.seed, preset: .iCloud, macs: Self.twoMacs(),
            events: shrunk, violation: violation
        )
        let text = SimScenarioPrinter.a1Style(scenario)
        for word in ["Setup", "Steps", "Wrong", "Must", "INV-S1"] {
            #expect(text.contains(word), "the printed scenario lacks \(word)")
        }
        let swift = SimScenarioPrinter.swiftTest(scenario)
        #expect(swift.contains("@Test(\"last writer wins by clock\")"))
        #expect(swift.contains(".expectNoViolation()"))
        #expect(swift.contains(".macs(["))
    }

    @Test("The shrinker returns a minimal failing sublist and leaves a passing list alone")
    func shrinkerMinimizes() {
        let events: [SimEvent] = (0..<30).map { .advance(milliseconds: Int64($0 + 1) * 1000) }
        // Fails when both the 7 s and the 23 s events are present.
        let needed: Set<Int64> = [7_000, 23_000]
        func failing(_ candidate: [SimEvent]) -> Bool {
            var present = Set<Int64>()
            for case .advance(let milliseconds) in candidate { present.insert(milliseconds) }
            return needed.isSubset(of: present)
        }
        let shrunk = SimShrinker().shrink(events, failing: failing)
        #expect(shrunk == [.advance(milliseconds: 7_000), .advance(milliseconds: 23_000)])
        let untouched = SimShrinker().shrink(Array(events.prefix(3)), failing: failing)
        #expect(untouched == Array(events.prefix(3)))
    }
}
