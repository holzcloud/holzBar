//
//  SimEngineJoinTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The join of plan 28-08 in the simulator: the real engine, a Mac that turns sync on for a folder whose
/// group holds a different value, and the answers that settle it (D-07, D-08, D-09), under the safety
/// oracles.
@Suite("SimEngineJoin")
struct SimEngineJoinTests {
    /// Mac A is in a group (launched with sync on and an empty folder, then edits S1); Mac B is a fresh
    /// install that holds `pre(B)` at S1 and has sync off.
    static func world(seed: UInt64 = 7, preset: SimProviderPreset? = nil, bValue: SimValue? = .string("pre(B)")) -> SimWorld {
        var defaults: [String: SimValue] = [:]
        if let bValue {
            defaults["S1"] = bValue
        }
        return SimWorld(
            seed: seed,
            macs: [
                SimMacSpec(.A, .redesign, generation: 26, running: true),
                SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, defaults: defaults, syncedFolder: "F1"),
            ],
            preset: preset,
            brainFactory: SimEngineTracerTests.redesignFactory,
            oracles: .safety
        )
    }

    /// A is in a group with `S1 = u1@S1`, and B turns sync on for the folder.
    static func joiningWorld(seed: UInt64 = 7, preset: SimProviderPreset? = nil) -> SimWorld {
        let world = world(seed: seed, preset: preset)
        world.step(.userEdit(mac: .A, unit: "S1"))
        SimEngineTracerTests.settle(world)
        world.step(.turnOn(mac: .B, folder: "F1"))
        SimEngineTracerTests.settle(world)
        return world
    }

    static func violations(_ world: SimWorld) -> [String] {
        world.oracleViolations.map { "\($0.id): \($0.description)" }
    }

    @Test("Turn On opens one sheet with one row that names both values")
    func oneRowNamesBothValues() throws {
        let world = Self.joiningWorld()
        let prompt = try #require(world.brain(of: .B).openPrompt)
        #expect(prompt.shown == [SimPromptUnit(unit: "S1", local: "pre(B)", folder: "u1@S1")])
        // Nothing of the folder is applied or published before the answer, and sync is still off.
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("pre(B)"))
        #expect(world.state(of: .B).enabled == false)
        #expect(world.state(of: .B).folderID == nil)
        let bFiles = world.writeLog.filter { $0.mac == .B }
        #expect(bFiles.isEmpty)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Use leaves B with A's value after its relaunch and publishes only what B authored")
    func useTakesTheFoldersValue() throws {
        let world = Self.joiningWorld()
        world.step(.answer(mac: .B, .use))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"))
        #expect(world.state(of: .B).running)
        #expect(world.state(of: .B).enabled)
        #expect(world.state(of: .B).folderID == "F1")
        #expect(world.brain(of: .B).openPrompt == nil)
        #expect(world.brain(of: .B).hint == nil)
        let state = try #require(SimMacRedesignProbe.state(of: world, .B))
        #expect(state.pendingJoin == nil)
        // B holds one entry for S1, its own answer, carrying A's value; A's dot is superseded.
        let live = state.replica.live(.whole("S1"))
        #expect(live.count == 1)
        #expect(live.first?.dot.mac == state.mac)
        #expect(live.first?.value == .string("u1@S1"))
        // A needs no question and no hint: B's entry holds the value A holds.
        #expect(world.brain(of: .A).openPrompt == nil)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .A)) == .string("u1@S1"))
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Keep gives A a Restart hint, and A has B's value after it restarts")
    func keepTakesThisMacsValue() throws {
        let world = Self.joiningWorld()
        world.step(.answer(mac: .B, .keep))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("pre(B)"))
        #expect(world.state(of: .B).enabled)
        #expect(world.brain(of: .B).openPrompt == nil)
        #expect(world.brain(of: .A).hint == "Settings changed on another Mac")
        #expect(world.brain(of: .A).openPrompt == nil)
        world.step(.restartApp(mac: .A))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .A)) == .string("pre(B)"))
        #expect(world.brain(of: .A).hint == nil)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Cancel leaves the folder as it was and sync off on B")
    func cancelWritesNothing() throws {
        let world = Self.joiningWorld()
        let writes = world.writeLog.count
        let folderBefore = world.replica(of: .A).entries
        world.step(.answer(mac: .B, .cancel))
        SimEngineTracerTests.settle(world)
        #expect(world.writeLog.count == writes)
        #expect(world.replica(of: .A).entries == folderBefore)
        #expect(world.state(of: .B).enabled == false)
        #expect(world.state(of: .B).folderID == nil)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("pre(B)"))
        #expect(world.brain(of: .B).openPrompt == nil)
        let state = try #require(SimMacRedesignProbe.state(of: world, .B))
        #expect(state.pendingJoin == nil)
        #expect(!state.isEnabled)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("The same join under the provider presets ends the same way and breaks no safety oracle", arguments: [1, 2, 3, 4] as [UInt64])
    func joinUnderPresets(seed: UInt64) throws {
        for preset in [SimProviderPreset.iCloud, .dropbox] {
            let world = Self.joiningWorld(seed: seed, preset: preset)
            let prompt = try #require(world.brain(of: .B).openPrompt, "seed \(seed) \(preset)")
            #expect(prompt.shown == [SimPromptUnit(unit: "S1", local: "pre(B)", folder: "u1@S1")])
            world.step(.answer(mac: .B, .use))
            SimEngineTracerTests.settle(world)
            #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"))
            #expect(Self.violations(world).isEmpty, "seed \(seed) \(preset): \(Self.violations(world))")
        }
    }
}

/// The control engines of analysis section 5.6: each is the real engine with one defense removed, and the
/// oracles must catch it within seeds 1 to 200 on the scenario that exposes it, with the first failing trace
/// shrunk to at most 14 events. The unmodified engine runs the same seeds with no violation.
@Suite("SimEngineVariants")
struct SimEngineVariantTests {
    static let seeds = UInt64(1)...200

    /// The first seed on which the variant is caught, its events and the shrunk events.
    static func catching<V: SimEngineVariant>(_ variant: V.Type) -> (seed: UInt64, events: [SimEvent], shrunk: [SimEvent])? {
        for seed in seeds {
            let events = V.events(seed: seed)
            guard V.found(V.world(seed: seed, events: events)) else { continue }
            let shrunk = SimShrinker().shrink(events) { candidate in
                V.found(V.world(seed: seed, events: candidate))
            }
            return (seed, events, shrunk)
        }
        return nil
    }

    static func check<V: SimEngineVariant>(_ variant: V.Type) throws {
        let caught = try #require(catching(variant), "\(variant) survived seeds 1 through 200")
        #expect(caught.shrunk.count <= 14, "\(variant) shrunk to \(caught.shrunk.count) events: \(caught.shrunk.map(\.canonical))")
        #expect(caught.shrunk.count < caught.events.count)
        #expect(V.found(V.world(seed: caught.seed, events: caught.shrunk)), "the shrunk trace must still fail")
        // The real engine runs the shrunk trace without a violation.
        let real = V.world(seed: caught.seed, events: caught.shrunk, removed: [])
        #expect(real.oracleViolations.isEmpty, "\(real.oracleViolations.map { "\($0.id): \($0.description)" })")
    }

    /// The unmodified engine on the seeds the control engine was run on: up to the one that caught it, and at
    /// least `minimum` seeds, so a quiet scenario is run long enough to mean something.
    static func survives<V: SimEngineVariant>(_ variant: V.Type, minimum: UInt64 = 25) {
        let caught = catching(variant)?.seed ?? seeds.upperBound
        for seed in UInt64(1)...min(max(caught, minimum), seeds.upperBound) {
            let world = V.world(seed: seed, events: V.events(seed: seed), removed: [])
            #expect(world.oracleViolations.isEmpty, "\(variant) seed \(seed): \(world.oracleViolations.map { "\($0.id): \($0.description)" })")
        }
    }

    @Test("Without the applied-context rule a change supersedes an entry its user never saw (INV-S1, INV-S7)")
    func noAppliedContext() throws {
        try Self.check(NoAppliedContext.self)
    }

    @Test("Overwriting an own file that was not read is caught (INV-S6, INV-Z6)")
    func unreadOwnFileOverwrite() throws {
        try Self.check(UnreadOwnFileOverwrite.self)
    }

    @Test("Minting at launch for a state that is no evidence is caught (INV-S2)")
    func mintAtLaunchUntrusted() throws {
        try Self.check(MintAtLaunchUntrusted.self)
    }

    @Test("Absence as a value is caught (INV-A6, INV-S1)")
    func equalToDefaultAsUnset() throws {
        try Self.check(EqualToDefaultAsUnset.self)
    }

    @Test("The unmodified engine survives the same seeds of every scenario with no violation")
    func realEngineSurvives() {
        Self.survives(NoAppliedContext.self)
        Self.survives(UnreadOwnFileOverwrite.self)
        Self.survives(MintAtLaunchUntrusted.self)
        Self.survives(EqualToDefaultAsUnset.self)
    }
}

/// The identity and restore events of the simulator, run against the real engine (analysis sections 4.5 and
/// 4.6.6 to 4.6.10): a clone, a copied account, Sigma lost or restored alone, preferences rolled back, and a
/// crash between two effects.
@Suite("SimEngineIdentity")
struct SimEngineIdentityTests {
    /// A and B are in a group; A's `S1` reached B, which applied it.
    static func group(seed: UInt64 = 5, preset: SimProviderPreset? = nil) -> SimWorld {
        let world = SimWorld(
            seed: seed,
            macs: [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, running: true)],
            preset: preset,
            brainFactory: SimEngineTracerTests.redesignFactory,
            oracles: .safety
        )
        world.step(.userEdit(mac: .A, unit: "S1"))
        SimEngineTracerTests.settle(world)
        world.step(.restartApp(mac: .B))
        SimEngineTracerTests.settle(world)
        return world
    }

    static func violations(_ world: SimWorld) -> [String] {
        world.oracleViolations.map { "\($0.id): \($0.description)" }
    }

    @Test("A clone on other hardware gets its own identity and keeps what it holds; the two never share an ID")
    func cloneGetsANewIdentity() throws {
        let world = Self.group()
        let before = try #require(SimMacRedesignProbe.id(of: world, .B))
        world.step(.clone(from: .A, to: .B))
        world.step(.launch(mac: .B))
        SimEngineTracerTests.settle(world)
        world.step(.restartApp(mac: .A))
        SimEngineTracerTests.settle(world)
        let a = try #require(SimMacRedesignProbe.id(of: world, .A))
        let b = try #require(SimMacRedesignProbe.id(of: world, .B))
        #expect(a != b)
        #expect(b != before)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"))
        let state = try #require(SimMacRedesignProbe.state(of: world, .B))
        #expect(state.previousMacIDs.contains { $0.rawValue == a }, "the cloned state kept its history under the old identity")
        #expect(world.brain(of: .B).openPrompt == nil)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("A copied account on the same hardware has another user ID, so it gets another identity")
    func copiedAccountGetsANewIdentity() throws {
        let world = Self.group()
        world.step(.copyAccount(from: .A, to: .B))
        world.step(.launch(mac: .B))
        SimEngineTracerTests.settle(world)
        let a = try #require(SimMacRedesignProbe.id(of: world, .A))
        let b = try #require(SimMacRedesignProbe.id(of: world, .B))
        #expect(a != b)
        #expect(world.state(of: .B).uid != world.state(of: .A).uid)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Sigma lost with the own file in the folder: the Mac joins again, adopts what is equal and asks nothing")
    func sigmaLostJoinsSilently() throws {
        let world = Self.group()
        world.step(.sigmaLost(mac: .A))
        world.step(.launch(mac: .A))
        SimEngineTracerTests.settle(world)
        #expect(world.brain(of: .A).openPrompt == nil)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .A)) == .string("u1@S1"))
        // Another edit afterwards still travels.
        world.step(.userEdit(mac: .A, unit: "S2"))
        SimEngineTracerTests.settle(world)
        world.step(.restartApp(mac: .B))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S2", in: world.defaults(of: .B)) != nil)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Sigma restored alone: the own file is joined first, no counter is reused and nothing is asked")
    func sigmaRestoredAlone() throws {
        let world = Self.group()
        world.step(.userEdit(mac: .A, unit: "S1"))
        SimEngineTracerTests.settle(world)
        let latest = SimUnits.value(of: "S1", in: world.defaults(of: .A))
        world.step(.restoreSigma(mac: .A))
        world.step(.launch(mac: .A))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .A)) == latest)
        #expect(world.brain(of: .A).openPrompt == nil)
        let state = try #require(SimMacRedesignProbe.state(of: world, .A))
        #expect(state.replica.live(.whole("S1")).count == 1)
        #expect(!state.captureDeferred, "capture ran once the own file was joined")
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("Preferences rolled back with Sigma kept: the restored values are asked about or wait, and never published as new")
    func preferencesRolledBack() throws {
        let world = Self.group()
        world.step(.restorePrefs(mac: .B))
        world.step(.launch(mac: .B))
        SimEngineTracerTests.settle(world)
        let published = world.writeLog.count
        // B's S1 is back to what the old preferences held; the group's value waits as a fast-forward.
        #expect(world.writeLog.filter { $0.mac == .B }.count <= published)
        world.step(.restartApp(mac: .B))
        SimEngineTracerTests.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"))
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("A full home restore with the Caches lost still counts above every counter that was used")
    func homeRestoreWithoutCaches() throws {
        let world = Self.group()
        world.step(.restoreHome(mac: .A, keepCaches: false))
        world.step(.launch(mac: .A))
        SimEngineTracerTests.settle(world)
        world.step(.userEdit(mac: .A, unit: "S3"))
        SimEngineTracerTests.settle(world)
        let own = try #require(SimMacRedesignProbe.id(of: world, .A))
        let counters = world.writeLog.filter { $0.mac == .A && $0.path.contains(own) }.compactMap { write -> UInt64? in
            guard case .success(let contents) = SyncDeviceFile.decode(write.data, fileName: "\(own).plist") else {
                return nil
            }
            return SyncMacID(own).map { contents.replica.context[$0] }
        }
        #expect(counters == counters.sorted(), "the counter of the own context never goes back")
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }

    @Test("A crash after the apply and before the persist leaves the old state; the next launch applies again and mints nothing")
    func crashBetweenApplyAndPersist() throws {
        let world = SimWorld(
            seed: 9,
            macs: [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, running: true)],
            brainFactory: SimEngineTracerTests.redesignFactory,
            oracles: .safety
        )
        world.step(.userEdit(mac: .A, unit: "S1"))
        SimEngineTracerTests.settle(world)
        world.step(.quit(mac: .B))
        let state = try #require(SimMacRedesignProbe.state(of: world, .B))
        let counter = state.counter
        // The first effect of B's launch applies the waiting value; the crash comes right after it.
        world.crashAfterEffect(1, on: .B)
        world.step(.launch(mac: .B))
        #expect(world.state(of: .B).running == false)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"), "the defaults took the value")
        let after = try #require(SimMacRedesignProbe.state(of: world, .B))
        #expect(after.applied[.whole("S1")] != state.replica.live(.whole("S1")).map(\.dot), "Sigma on disk is still the old one")
        world.step(.launch(mac: .B))
        SimEngineTracerTests.settle(world)
        let final = try #require(SimMacRedesignProbe.state(of: world, .B))
        #expect(final.counter == counter, "nothing was minted")
        #expect(final.replica.live(.whole("S1")).map(\.value) == [.string("u1@S1")])
        #expect(world.brain(of: .B).hint == nil)
        #expect(Self.violations(world).isEmpty, "\(Self.violations(world))")
    }
}
