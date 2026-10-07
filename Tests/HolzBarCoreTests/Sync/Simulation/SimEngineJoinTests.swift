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
