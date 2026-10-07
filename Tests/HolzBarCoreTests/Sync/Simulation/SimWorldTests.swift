import Foundation
import Testing

@Suite("SimWorld")
struct SimWorldTests {
    private let hour: Int64 = 3600 * 1000

    /// A random event stream over the given Macs, drawn from one seeded stream (200 events by default).
    static func randomEvents(seed: UInt64, macs: [SimMacName], count: Int = 200) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("events")
        let units = ["ShowOnHover", "UseIceBar", "ItemSections/com.foo", "Hotkeys/toggle", "RehideInterval"]
        var events: [SimEvent] = []
        for _ in 0..<count {
            let mac = random.pick(macs)
            let event: SimEvent
            switch random.int(in: 0...11) {
            case 0: event = .launch(mac: mac)
            case 1: event = .quit(mac: mac)
            case 2: event = .userEdit(mac: mac, unit: random.pick(units))
            case 3: event = .userDelete(mac: mac, unit: random.pick(units))
            case 4: event = .setHotkey(mac: mac, action: "toggle", combo: random.int(in: 0...2))
            case 5: event = .autoPlace(mac: mac, unit: random.pick(units))
            case 6: event = .advance(milliseconds: Int64(random.int(in: 1...20)) * 1000)
            case 7: event = .clockStep(mac: mac, milliseconds: Int64(random.int(in: -3...3)) * 3600 * 1000)
            case 8: event = .answer(mac: mac, random.pick([SimAnswer.use, .later, .keep]))
            case 9: event = .restartApp(mac: mac)
            case 10: event = .crash(mac: mac)
            default: event = .advance(milliseconds: 6000)
            }
            events.append(event)
        }
        return events
    }

    private func makeWorld(seed: UInt64) -> SimWorld {
        SimWorld(seed: seed, macs: [SimMacSpec(.A, .beta1), SimMacSpec(.B, .beta1)])
    }

    @Test("The same seed gives the same trace hash and another seed another one")
    func traceHashIsReproducible() {
        func hash(seed: UInt64) -> String {
            let world = makeWorld(seed: seed)
            world.run(Self.randomEvents(seed: seed, macs: [.A, .B]))
            return world.traceHash
        }
        let first = hash(seed: 42)
        #expect(first == hash(seed: 42))
        #expect(first != hash(seed: 43))
        #expect(first.count == 64)
    }

    @Test("The generator is a stable xoshiro256 stream and forks are independent of use")
    func randomIsStable() {
        var a = SimRandom(seed: 7)
        var b = SimRandom(seed: 7)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
        var used = SimRandom(seed: 7)
        _ = used.next()
        var forkOfUsed = used.fork("x")
        var forkOfFresh = SimRandom(seed: 7).fork("x")
        #expect(forkOfUsed.next() == forkOfFresh.next())
        var other = SimRandom(seed: 7).fork("y")
        var same = SimRandom(seed: 7).fork("x")
        #expect(other.next() != same.next())
        #expect(SimRandom.fnv1a("holzBar") == SimRandom.fnv1a("holzBar"))
        var delays = SimRandom(seed: 1)
        let samples = (0..<500).map { _ in delays.heavyTailedDelay(medianMilliseconds: 1000) }
        #expect(samples.allSatisfy { $0 > 0 })
        #expect(samples.max()! > 5_000)
    }

    @Test("A virtual clock keeps per-Mac offsets and never reads real time")
    func clockOffsets() {
        var clock = SimClock()
        clock.setOffset(2 * hour, of: .A)
        clock.advance(to: 1000)
        #expect(clock.wallClockMilliseconds(of: .A) - clock.wallClockMilliseconds(of: .B) == 2 * hour)
        clock.step(.B, by: -30 * 24 * hour)
        #expect(clock.offset(of: .B) == -SimClock.maximumOffsetMilliseconds)
    }

    @Test("Values round trip through a property list and tokens are found")
    func valueRoundTrip() throws {
        let value = SimValue.dictionary([
            "a": .string("u1@ShowOnHover"), "b": .int(3), "c": .bool(true),
            "d": .array([.string("auto-A-2"), .string("plain")]), "e": .data(Data([1, 2, 3])),
        ])
        let data = try PropertyListSerialization.data(fromPropertyList: value.propertyList, format: .xml, options: 0)
        let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        #expect(SimValue(propertyList: decoded) == value)
        #expect(value.tokens == ["auto-A-2", "u1@ShowOnHover"])
        #expect(SimValue.origin(ofToken: "u17@ItemSections/com.foo") == .user(k: 17, unit: "ItemSections/com.foo"))
        #expect(SimValue.origin(ofToken: "auto-A-42") == .automatic(mac: "A", k: 42))
        #expect(SimValue.origin(ofToken: "pre(B)") == .pre(mac: "B"))
        #expect(SimValue.origin(ofToken: "plain") == nil)
    }

    @Test("A beta1 peer applies another peer's file silently with remove-missing")
    func beta1AppliesWithRemoveMissing() throws {
        let world = SimWorld(seed: 1, macs: [
            SimMacSpec(.A, .beta1, running: true),
            SimMacSpec(.B, .beta1, defaults: ["RehideInterval": .string("only-on-B"), "ShowOnHover": .string("B-value")]),
        ])
        world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
        let token = try #require(world.defaults(of: .A)["ShowOnHover"])
        #expect(token == .string("u1@ShowOnHover"))
        world.advance(seconds: 5)
        world.step(.launch(mac: .B))
        #expect(world.defaults(of: .B)["ShowOnHover"] == token)
        #expect(world.defaults(of: .B)["RehideInterval"] == nil)
        #expect(world.defaults(of: .B)["HasImportedIceSettings"] == .bool(true))
    }

    @Test("A beta1 peer pushes 5 seconds after a change and not before")
    func beta1PushesAfterDebounce() throws {
        let world = SimWorld(seed: 2, macs: [SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1)])
        let launchFile = world.replica(of: .A).entry(SimMacBeta1.filePath)
        world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
        world.advance(seconds: 4)
        #expect(world.replica(of: .A).entry(SimMacBeta1.filePath) == launchFile)
        world.advance(seconds: 2)
        #expect(world.replica(of: .A).entry(SimMacBeta1.filePath) != launchFile)
        guard case .present(let data) = world.replica(of: .B).entry(SimMacBeta1.filePath) else {
            Issue.record("B's replica has no file")
            return
        }
        let heldTokens = SimMacBeta1().heldTokens(inFile: SimMacBeta1.filePath, data: data)
        #expect(heldTokens == ["u1@ShowOnHover"])
    }

    @Test("A beta1 peer ignores a file dated more than an hour in its future")
    func beta1IgnoresFutureFile() {
        let world = SimWorld(seed: 3, macs: [
            SimMacSpec(.A, .beta1, running: true, clockOffsetMilliseconds: 2 * hour),
            SimMacSpec(.B, .beta1, defaults: ["ShowOnHover": .string("B-value")]),
        ])
        world.step(.userEdit(mac: .A, unit: "UseIceBar"))
        world.advance(seconds: 5)
        world.step(.launch(mac: .B))
        #expect(world.defaults(of: .B)["UseIceBar"] == nil)
        #expect(world.defaults(of: .B)["ShowOnHover"] == .string("B-value"))
        #expect(world.defaults(of: .B)["HasImportedIceSettings"] == nil)
    }

    @Test("A beta1 peer ignores a file over 1 MiB")
    func beta1IgnoresOversizeFile() {
        let world = SimWorld(seed: 4, macs: [
            SimMacSpec(.A, .beta1, running: true),
            SimMacSpec(.B, .beta1, defaults: ["ShowOnHover": .string("B-value")]),
        ])
        world.step(.oversizeIcon(mac: .A))
        world.advance(seconds: 5)
        world.step(.launch(mac: .B))
        #expect(world.defaults(of: .B)["IceIcon"] == nil)
        #expect(world.defaults(of: .B)["ShowOnHover"] == .string("B-value"))
    }

    @Test("A running beta1 peer asks before applying, Later records nothing and Restart applies")
    func beta1PromptsOnFolderSignal() throws {
        let world = SimWorld(seed: 5, macs: [
            SimMacSpec(.A, .beta1, running: true),
            SimMacSpec(.B, .beta1, running: true, defaults: ["RehideInterval": .string("only-on-B")]),
        ])
        world.advance(seconds: 1)
        world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
        world.advance(seconds: 6)
        let prompt = try #require(world.brain(of: .B).openPrompt)
        #expect(prompt.title == "Settings changed on another Mac")
        world.step(.answer(mac: .B, .later))
        #expect(world.brain(of: .B).openPrompt == nil)
        #expect(world.defaults(of: .B)["ShowOnHover"] == nil)
        // The next change on A raises it again; Restart applies the file silently with remove-missing.
        world.step(.userEdit(mac: .A, unit: "UseIceBar"))
        world.advance(seconds: 6)
        #expect(world.brain(of: .B).openPrompt != nil)
        world.step(.answer(mac: .B, .use))
        #expect(world.defaults(of: .B)["UseIceBar"] == .string("u2@UseIceBar"))
        #expect(world.defaults(of: .B)["RehideInterval"] == nil)
        #expect(world.state(of: .B).running)
    }

    @Test("No simulation code reads the real clock, the system generator or real concurrency")
    func noRealTimeOrConcurrency() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("Tests.swift") }
        // Spelled in pieces so this file does not contain the patterns it forbids elsewhere.
        let forbidden = ["Da" + "te()", "Dispatch" + "Queue", "Ta" + "sk {", "Task" + ".detached", "Thre" + "ad."]
        // The system generator is a call on a type (`Int.ran` + `dom(in:)`); the run mode `SimRunMode.random(steps:)` is not.
        let systemGenerator = try NSRegularExpression(pattern: "([A-Za-z0-9_]+)\\.ran" + "dom\\(")
        for file in files {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            for pattern in forbidden {
                #expect(!text.contains(pattern), "\(file) contains \(pattern)")
            }
            let range = NSRange(text.startIndex..., in: text)
            for match in systemGenerator.matches(in: text, range: range) {
                let owner = (text as NSString).substring(with: match.range(at: 1))
                #expect(owner == "SimRunMode", "\(file) calls the system generator on \(owner)")
            }
        }
    }
}
