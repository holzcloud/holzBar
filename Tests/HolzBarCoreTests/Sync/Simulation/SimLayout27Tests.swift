//
//  SimLayout27Tests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The macOS 27 families in the simulator (plan 28-09): the real engine, two generation-27 Macs and
/// one generation-26 Mac that relays what it cannot apply, under the safety and layout oracles.
@Suite("SimLayout27")
struct SimLayout27Tests {
    static let bundle = "com.app.a"
    static let unit = "l27/com.app.a"

    static func world(seed: UInt64 = 7, preset: SimProviderPreset? = .iCloud, oracles: SimOracleSet = .safety) -> SimWorld {
        SimWorld(
            seed: seed,
            macs: [
                SimMacSpec(.A, .redesign, generation: 27, running: true),
                SimMacSpec(.B, .redesign, generation: 27, running: true),
                SimMacSpec(.C, .redesign, generation: 26, running: true),
            ],
            preset: preset,
            brainFactory: SimEngineTracerTests.redesignFactory,
            oracles: oracles
        )
    }

    static func violations(_ world: SimWorld) -> [String] {
        world.oracleViolations.map { "\($0.id): \($0.description)" }
    }

    /// The entries of `l27/<bundle>` that a Mac's own file carries, by the last write of that Mac.
    static func ownFileEntries(_ world: SimWorld, _ mac: SimMacName, unit key: SyncUnitKey) throws -> [SyncEntry] {
        let own = try #require(SimMacRedesignProbe.id(of: world, mac))
        let path = SimFolderIO.directory + "/\(own).plist"
        let write = try #require(world.writeLog.last { $0.mac == mac && $0.path == path })
        let file = try SyncDeviceFile.decode(write.data, fileName: "\(own).plist").get()
        return file.replica.live(key)
    }

    @Test("A move on macOS 27 reaches another macOS 27 Mac as an explicit entry; macOS 26 relays it untouched", arguments: [7, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12] as [UInt64])
    func moveTravels(seed: UInt64) throws {
        let world = Self.world(seed: seed)
        world.step(.moveApp27(mac: .A, bundle: Self.bundle, section: 1))
        SimEngineTracerTests.settle(world)

        let token = try #require(SimUnits.value(of: Self.unit, in: world.defaults(of: .A)))
        // B shows the Restart hint and still holds nothing; after its restart it holds the token.
        #expect(world.brain(of: .B).hint != nil)
        #expect(SimUnits.value(of: Self.unit, in: world.defaults(of: .B)) == nil)
        world.step(.restartApp(mac: .B))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: Self.unit, in: world.defaults(of: .B)) == token)
        #expect(world.brain(of: .B).hint == nil)

        // C neither compares, shows nor applies it.
        #expect(world.brain(of: .C).hint == nil)
        #expect(world.brain(of: .C).openPrompt == nil)
        #expect(SimUnits.value(of: Self.unit, in: world.defaults(of: .C)) == nil)
        world.step(.restartApp(mac: .C))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: Self.unit, in: world.defaults(of: .C)) == nil)
        #expect(world.brain(of: .C).hint == nil)

        // C's own file still carries the entry, with A's dot unchanged.
        let key = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: Self.bundle)
        let fromA = try Self.ownFileEntries(world, .A, unit: key)
        let fromC = try Self.ownFileEntries(world, .C, unit: key)
        #expect(fromA.count == 1)
        #expect(fromC.map(\.dot) == fromA.map(\.dot))
        #expect(fromC.map(\.payload) == fromA.map(\.payload))
        #expect(world.oracleViolations.isEmpty, "\(Self.violations(world))")
    }

    // MARK: Random worlds

    static func specs() -> [SimMacSpec] {
        [
            SimMacSpec(.A, .redesign, generation: 27, running: true),
            SimMacSpec(.B, .redesign, generation: 27, running: true),
            SimMacSpec(.C, .redesign, generation: 26, running: true),
        ]
    }

    /// The events of one seed: user moves, profile saves, renames, deletes and applications, automatic placements,
    /// seeding and an OS upgrade of the macOS 26 Mac, around launches, restarts, answers and the passing of time.
    static func events(seed: UInt64, steps: Int = 36) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("layout27-events")
        let bundles = SimKeys.apps27
        let profiles = ["p1", "p2"]
        let macs27 = [SimMacName.A, .B]
        var events: [SimEvent] = []
        var upgraded = false
        for _ in 0..<steps {
            let mac = random.pick(macs27)
            switch random.int(in: 0...19) {
            case 0, 1, 2, 3: events.append(.moveApp27(mac: mac, bundle: random.pick(bundles), section: random.int(in: 0...2)))
            case 4: events.append(.saveProfile(mac: mac, profile: random.pick(profiles)))
            case 5: events.append(.renameProfile(mac: mac, profile: random.pick(profiles)))
            case 6: events.append(.deleteProfile(mac: mac, profile: random.pick(profiles)))
            case 7, 8: events.append(.applyProfile(mac: mac, profile: random.pick(profiles), byUser: random.chance(0.6)))
            case 9: events.append(.seed27(mac: random.chance(0.8) ? mac : .C))
            case 10: events.append(.placeNewApp27(mac: mac, bundle: random.pick(bundles)))
            case 11:
                if !upgraded, random.chance(0.3) {
                    upgraded = true
                    events.append(.upgradeOS(mac: .C))
                    events.append(.launch(mac: .C))
                } else {
                    events.append(.restartApp(mac: random.pick([.A, .B, .C])))
                }
            case 12: events.append(.restartApp(mac: random.pick([.A, .B, .C])))
            case 13: events.append(.answer(mac: random.pick([.A, .B, .C]), random.pick([.use, .keep])))
            case 14: events.append(.quit(mac: random.pick([.A, .B, .C])))
            case 15: events.append(.launch(mac: random.pick([.A, .B, .C])))
            default: events.append(.advance(milliseconds: random.pick([1_000, 2_000, 6_000, 12_000, 30_000, 300_000])))
            }
        }
        // C moves and saves only after its upgrade, which the world ignores before.
        if upgraded {
            events.append(.moveApp27(mac: .C, bundle: random.pick(bundles), section: random.int(in: 0...2)))
        }
        return events
    }

    static func run(seed: UInt64, preset: SimProviderPreset, oracles: SimOracleSet = .safety) -> SimWorld {
        let world = SimWorld(seed: seed, macs: specs(), preset: preset, brainFactory: SimEngineTracerTests.redesignFactory, oracles: oracles)
        world.run(events(seed: seed))
        return world
    }

    /// Lets every Mac relaunch and answer what it is asked with Use, until nothing is open any more.
    static func drain(_ world: SimWorld) {
        SimDrain.settle(world)
        for _ in 0..<6 {
            let writes = world.writeLog.count
            for mac in world.macs.keys.sorted() {
                world.step(world.macs[mac]?.running == true ? .restartApp(mac: mac) : .launch(mac: mac))
            }
            SimDrain.settle(world)
            var rounds = 0
            while rounds < 6, let mac = world.macs.keys.sorted().first(where: { world.brains[$0]?.openPrompt != nil }) {
                world.step(.answer(mac: mac, .use))
                SimDrain.settle(world)
                rounds += 1
            }
            if world.writeLog.count == writes, !world.macs.keys.contains(where: { world.brains[$0]?.openPrompt != nil || world.brains[$0]?.hint != nil }) {
                break
            }
        }
    }

    /// The units of the macOS 27 families where the generation-27 Macs hold different values although the user
    /// made one of them. A value that only holzBar placed need not agree: only the user's intent syncs.
    static func disagreements(_ world: SimWorld) -> [String] {
        let macs = world.macs.keys.sorted().filter { world.macs[$0]?.generation == 27 }
        var units = Set<String>()
        for mac in macs {
            for (unit, _) in SimUnits.units(of: world.defaults(of: mac)) where SimLayout27Oracles.isScoped(unit) && unit != SimUnits.known27 {
                units.insert(unit)
            }
        }
        var found: [String] = []
        for unit in units.sorted() {
            let values = macs.map { SimUnits.value(of: unit, in: world.defaults(of: $0)) }
            let user = values.contains { $0?.tokens.contains { world.groundTruth.origin(of: $0) == .user } ?? false }
            if user, Set(values).count > 1 {
                found.append("\(unit): \(zip(macs, values).map { "\($0)=\($1?.canonical ?? "-")" }.joined(separator: " "))")
            }
        }
        return found
    }

    /// The most seeds a plain `swift test` runs per preset; the gate runs seeds 1 to 100 with `SYNC_L27_SEEDS=100`
    /// (a world with its drain takes seconds, so the plain run stays short).
    static let defaultSeeds: UInt64 = 10

    /// Seeds 1 to 100 in chunks of 5, so the cores share the work.
    static let chunks: [SimChunk] = [SimProviderPreset.iCloud, .hostile].flatMap { preset in
        stride(from: UInt64(1), through: 100, by: 5).map { SimChunk(preset: preset, first: $0, last: $0 + 4) }
    }

    struct SimChunk: Sendable, CustomTestStringConvertible {
        var preset: SimProviderPreset
        var first: UInt64
        var last: UInt64

        var testDescription: String { "\(preset) seeds \(first) to \(last)" }
    }

    @Test("Random worlds of two macOS 27 Macs and one macOS 26 Mac end with no layout-oracle violation and agree on the arrangement", arguments: chunks)
    func randomWorlds(chunk: SimChunk) async {
        await HeavyTestGate.run {
            let environment = ProcessInfo.processInfo.environment
            let limit = environment["SYNC_L27_SEEDS"].flatMap { UInt64($0) } ?? Self.defaultSeeds
            var failures: [String] = []
            for seed in chunk.first...chunk.last where seed <= limit {
                let world = Self.run(seed: seed, preset: chunk.preset)
                Self.drain(world)
                for violation in world.oracleViolations.prefix(2) {
                    failures.append("seed \(seed): \(violation.id) \(violation.description)")
                }
                for difference in Self.disagreements(world).prefix(2) {
                    failures.append("seed \(seed): disagreement at \(difference)")
                }
                // A Mac of macOS 26 keeps its layout and profiles as they were: it never had any of the families.
                if world.macs[.C]?.generation == 26 {
                    let held = SimUnits.units(of: world.defaults(of: .C)).filter { SimLayout27Oracles.isScoped($0.unit) }
                    if !held.isEmpty {
                        failures.append("seed \(seed): the macOS 26 Mac holds \(held.map(\.unit))")
                    }
                }
            }
            #expect(failures.isEmpty, "\(failures.count) violations\n\(failures.prefix(25).joined(separator: "\n"))")
        }
    }

    /// The first seed of 1 to 60 on which a world run by `make` ends with a violation of one of `ids`.
    static func firstCatch(_ ids: Set<SimInvariantID>, _ make: @escaping @Sendable () -> SimMacRedesign) -> UInt64? {
        for seed in UInt64(1)...60 {
            let world = SimWorld(seed: seed, macs: specs(), preset: .iCloud, brainFactory: { _, _ in make() }, oracles: .safety)
            world.run(events(seed: seed))
            if world.oracleViolations.contains(where: { ids.contains($0.id) }) {
                return seed
            }
        }
        return nil
    }

    @Test("The oracles catch an engine that lets macOS 26 apply the families")
    func seededGenerationScopeDefect() {
        let seed = Self.firstCatch(["INV-L1", "INV-N1", "INV-L2", "INV-L3"]) { SimMacRedesign(table: SimEngineUnits.table(scoped: false)) }
        #expect(seed != nil, "an engine without the generation scope survived seeds 1 to 60")
    }

    @Test("The oracles catch an engine that cannot tell holzBar's own stores from the user's moves")
    func seededAutomaticStoreDefect() {
        let seed = Self.firstCatch(["INV-A3", "INV-S1", "INV-S2"]) {
            var brain = SimMacRedesign()
            brain.automaticStoresAreIntents = true
            return brain
        }
        #expect(seed != nil, "an engine that publishes automatic placements survived seeds 1 to 60")
    }

    @Test("The same move to the visible section is the explicit value, not a deletion")
    func moveToVisibleIsExplicit() throws {
        let world = Self.world(preset: nil)
        world.step(.moveApp27(mac: .A, bundle: Self.bundle, section: 1))
        SimEngineTracerTests.settle(world)
        world.step(.restartApp(mac: .B))
        SimEngineTracerTests.settle(world)
        world.step(.moveApp27(mac: .B, bundle: Self.bundle, section: 0))
        SimEngineTracerTests.settle(world)
        let key = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: Self.bundle)
        let entries = try Self.ownFileEntries(world, .B, unit: key)
        #expect(entries.count == 1)
        #expect(entries.first?.payload != .deleted)
        #expect(world.oracleViolations.isEmpty, "\(Self.violations(world))")
    }
}
