//
//  SimEngineTracerTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The tracer of plan 28-07: the real engine in the simulator carries one setting from one Mac
/// to another, under the safety oracles.
@Suite("SimEngineTracer")
struct SimEngineTracerTests {
    static func redesignFactory(_ version: SimMacVersion, _ mac: SimMacName) -> any SimSyncBrain {
        switch version {
        case .redesign, .redesignSkew: SimMacRedesign()
        case .beta1: SimMacBeta1()
        case .beta2: SimMacBeta2()
        }
    }

    static func world(seed: UInt64 = 7, preset: SimProviderPreset? = .iCloud) -> SimWorld {
        SimWorld(
            seed: seed,
            macs: [
                SimMacSpec(.A, .redesign, generation: 26, running: true),
                SimMacSpec(.B, .redesign, generation: 27, running: true),
            ],
            preset: preset,
            brainFactory: redesignFactory,
            oracles: .safety
        )
    }

    /// Lets the provider deliver, the dataless files arrive and the 15-minute poll run twice.
    static func settle(_ world: SimWorld) {
        SimDrain.settle(world)
        world.advance(seconds: 16 * 60)
        SimDrain.settle(world)
    }

    @Test("A setting edited on Mac A reaches Mac B as a Restart hint and then as an applied value", arguments: [7, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12] as [UInt64])
    func settingTravelsFromAToB(seed: UInt64) {
        let world = Self.world(seed: seed)
        world.step(.userEdit(mac: .A, unit: "S1"))
        Self.settle(world)

        // B shows the Restart hint and still holds the old value.
        #expect(world.brain(of: .B).hint != nil)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == nil)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .A)) == .string("u1@S1"))

        // Restart applies it.
        world.step(.restartApp(mac: .B))
        Self.settle(world)
        #expect(SimUnits.value(of: "S1", in: world.defaults(of: .B)) == .string("u1@S1"))
        #expect(world.brain(of: .B).hint == nil)

        // Relaunches change nothing: the provider sees no further write.
        let writes = world.writeLog.count
        for _ in 0..<3 {
            world.step(.restartApp(mac: .A))
            world.step(.restartApp(mac: .B))
            Self.settle(world)
        }
        #expect(world.writeLog.count == writes, "relaunches wrote \(world.writeLog.count - writes) files")
        #expect(world.brain(of: .A).hint == nil)
        #expect(world.brain(of: .B).hint == nil)
        #expect(world.oracleViolations.isEmpty, "\(world.oracleViolations.map { "\($0.id): \($0.description)" })")
    }

    @Test("A change is persisted before the own file is written, and the file carries it")
    func persistsBeforeWriting() throws {
        let world = Self.world(preset: nil)
        world.step(.userEdit(mac: .A, unit: "S1"))
        Self.settle(world)
        let own = try #require(SimMacRedesignProbe.id(of: world, .A))
        let write = try #require(world.writeLog.first { $0.mac == .A && $0.path == SimFolderIO.directory + "/\(own).plist" })
        let file = try SyncDeviceFile.decode(write.data, fileName: "\(own).plist").get()
        let entry = try #require(file.replica.live(.whole("S1")).first)
        #expect(entry.value == .string("u1@S1"))
        // Sigma holds the entry the file holds, and the counter mirror is at least its counter.
        let state = try #require(SimMacRedesignProbe.state(of: world, .A))
        #expect(state.replica.live(.whole("S1")).map(\.dot) == [entry.dot])
        #expect(state.publishedCounter >= entry.dot.n)
        guard case .int(let mirror)? = world.defaults(of: .A)[SimMacRedesign.counterMirrorKey] else {
            Issue.record("the counter mirror is missing")
            return
        }
        #expect(UInt64(mirror) >= entry.dot.n)
    }

    @Test("Two Macs that edit different settings both keep them without a question")
    func differentUnitsMergeWithoutAQuestion() {
        let world = Self.world(preset: nil)
        world.step(.userEdit(mac: .A, unit: "S1"))
        world.step(.userEdit(mac: .B, unit: "S2"))
        Self.settle(world)
        world.step(.restartApp(mac: .A))
        world.step(.restartApp(mac: .B))
        Self.settle(world)
        for mac in [SimMacName.A, .B] {
            #expect(SimUnits.value(of: "S1", in: world.defaults(of: mac)) == .string("u1@S1"))
            #expect(SimUnits.value(of: "S2", in: world.defaults(of: mac)) == .string("u2@S2"))
            #expect(world.brain(of: mac).openPrompt == nil)
        }
        #expect(world.oracleViolations.isEmpty, "\(world.oracleViolations.map { "\($0.id): \($0.description)" })")
    }
}

/// Reads what a simulated redesigned Mac keeps, for tests.
enum SimMacRedesignProbe {
    static func id(of world: SimWorld, _ mac: SimMacName) -> String? {
        (world.brain(of: mac) as? SimMacRedesign)?.report().deviceID
    }

    /// The tokens of the values that the state in the Mac's Sigma blob has applied; `nil` when the Mac has no state.
    static func appliedTokens(of world: SimWorld, _ mac: SimMacName) -> Set<String>? {
        guard let state = state(of: world, mac) else { return nil }
        var applied = Set<String>()
        for (key, dots) in state.applied {
            for entry in state.replica.live(key) where dots.contains(entry.dot) {
                applied.formUnion(entry.value.flatMap { SimValue(sync: $0) }?.tokens ?? [])
            }
        }
        return applied
    }

    /// The state in the Mac's Sigma blob.
    static func state(of world: SimWorld, _ mac: SimMacName) -> SyncState? {
        guard let data = world.state(of: mac).sigma, case .state(let state) = SyncStateCodec.decode(data) else {
            return nil
        }
        return state
    }
}
