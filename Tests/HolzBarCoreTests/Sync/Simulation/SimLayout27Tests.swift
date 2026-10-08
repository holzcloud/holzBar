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
