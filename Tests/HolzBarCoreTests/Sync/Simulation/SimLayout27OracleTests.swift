//
//  SimLayout27OracleTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// One positive and one negative test per layout oracle, on hand-built worlds (plan 28-09, Task 3). A violation
/// shows up when a scripted brain misbehaves and stays away when it does not.
@Suite("SimLayout27Oracles")
struct SimLayout27OracleTests {
    private typealias Oracles = SimOracleTests

    static let unit = "l27/com.app.a"
    static let token1 = "u1@l27/com.app.a"
    /// The second move of the application in a world where a user edit came between the two moves.
    static let token3 = "u3@l27/com.app.a"

    static func running(_ name: SimMacName, generation: Int, defaults: [String: SimValue] = [:]) -> SimMacSpec {
        Oracles.running(name, generation: generation, defaults: defaults)
    }

    static func world(_ specs: [SimMacSpec], _ brains: [SimMacName: SimScriptedBrain] = [:], ids: [SimInvariantID]) -> SimWorld {
        Oracles.world(specs, brains, ids: ids)
    }

    /// A brain of Mac `name` that publishes the file `build` gives at each change of its own defaults.
    static func publishing(_ name: String, _ build: @escaping @Sendable (Int) -> Data) -> SimScriptedBrain {
        Oracles.publishing(id: name, path: "holzBar/Macs/\(name).plist", build)
    }

    /// A brain that shows a sheet about `unit` at its first change of the defaults.
    static func asking(about unit: String, id: String) -> SimScriptedBrain {
        Oracles.asking(SimPrompt(id: 1, title: "Settings differ", shown: [SimPromptUnit(unit: unit, local: "u8@\(unit)", folder: "u9@\(unit)")]), id: id)
    }

    // MARK: Registry

    @Test("The layout set carries INV-L1 to INV-L4, INV-L6, INV-K1 and the automatic-store rule, and the safety set includes it")
    func registry() {
        let ids = SimOracleSet.layout27.ids
        for required: SimInvariantID in ["INV-L1", "INV-L2", "INV-L3", "INV-L4", "INV-L6", "INV-K1", "INV-A3"] {
            #expect(ids.contains(required), "missing \(required)")
            #expect(SimOracleSet.safety.ids.contains(required), "the safety set lacks \(required)")
        }
        #expect(SimLayout27Oracles.oracle("INV-L1") != nil)
    }

    @Test("The layout oracles are quiet in a world without a macOS 27 Mac")
    func quietWithoutGeneration27() {
        let world = Self.world([Self.running(.A, generation: 26), Self.running(.B, generation: 26)], ids: SimOracleSet.layout27.ids)
        world.run([.userEdit(mac: .A, unit: "ShowOnHover"), .userEdit(mac: .B, unit: "ShowOnHover")])
        #expect(world.oracleViolations.isEmpty)
    }

    // MARK: INV-L1

    @Test("INV-L1 fires on a sheet of a macOS 26 Mac about the other generation's units")
    func l1Sheet() {
        func world(about unit: String) -> SimWorld {
            let brain = Self.asking(about: unit, id: "B")
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L1"])
            world.step(.userEdit(mac: .B, unit: "ShowOnHover"))
            return world
        }
        Oracles.check("INV-L1", bad: { world(about: Self.unit) }, good: { world(about: "ShowOnHover") })
    }

    @Test("INV-L1 fires on a sync-caused change of a unit of the other generation on a macOS 26 Mac")
    func l1Apply() {
        func world(applying: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "B")
            brain.changedScript = { context, _ in
                if applying { SimUnits.set(SimLayout27OracleTests.unit, to: .string(SimLayout27OracleTests.token1), in: &context.defaults) }
            }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L1"])
            world.step(.userEdit(mac: .B, unit: "ShowOnHover"))
            return world
        }
        Oracles.check("INV-L1", bad: { world(applying: true) }, good: { world(applying: false) })
    }

    @Test("INV-L1 fires on a hint of a macOS 26 Mac that no unit it compares justifies")
    func l1Hint() {
        func world(otherChange: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "B")
            brain.changedScript = { _, brain in brain.hintText = "Choose Settings" }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L1"])
            world.run((otherChange ? [.userEdit(mac: .A, unit: "ShowOnHover")] : []) + [.userEdit(mac: .B, unit: "UseIceBar")])
            return world
        }
        Oracles.check("INV-L1", bad: { world(otherChange: false) }, good: { world(otherChange: true) })
    }

    // MARK: INV-L2

    @Test("INV-L2 fires when a macOS 26 Mac publishes a value of the families that no macOS 27 user made")
    func l2() {
        func world(token: String) -> SimWorld {
            let brain = Self.publishing("B") { _ in SimScriptedBrain.file(tokens: [token], mentioned: [Self.unit]) }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L2"])
            world.run([.moveApp27(mac: .A, bundle: "com.app.a", section: 1), .userEdit(mac: .B, unit: "ShowOnHover")])
            return world
        }
        // A relayed value was made by the user of the generation-27 Mac; an invented one was made by nobody.
        Oracles.check("INV-L2", bad: { world(token: "u7@l27/com.app.b") }, good: { world(token: Self.token1) })
    }

    @Test("INV-L2 fires on a deletion of a unit of the families that no macOS 27 user made")
    func l2Deletion() {
        func world(deleting: Bool) -> SimWorld {
            let brain = Self.publishing("B") { _ in SimScriptedBrain.file(tokens: [], deleted: deleting ? [Self.unit] : []) }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L2"])
            world.run([.moveApp27(mac: .A, bundle: "com.app.a", section: 1), .userEdit(mac: .B, unit: "ShowOnHover")])
            return world
        }
        Oracles.check("INV-L2", bad: { world(deleting: true) }, good: { world(deleting: false) })
    }

    // MARK: INV-L3

    @Test("INV-L3 fires when a macOS 26 Mac drops a relayed value from its next file")
    func l3() {
        func world(keeping: Bool) -> SimWorld {
            let brain = Self.publishing("B") { count in
                SimScriptedBrain.file(tokens: count == 1 || keeping ? [Self.token1] : [], mentioned: [Self.unit])
            }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-L3"])
            world.run([.moveApp27(mac: .A, bundle: "com.app.a", section: 1), .userEdit(mac: .B, unit: "ShowOnHover"), .userEdit(mac: .B, unit: "UseIceBar")])
            return world
        }
        Oracles.check("INV-L3", bad: { world(keeping: false) }, good: { world(keeping: true) })
    }

    // MARK: INV-L4

    @Test("INV-L4 fires when a macOS 26 Mac replaces a relayed value by one that did not know of it")
    func l4() {
        func world(second: String, sameMac: Bool) -> SimWorld {
            let brain = Self.publishing("C") { count in
                SimScriptedBrain.file(tokens: [count == 1 ? Self.token1 : second], mentioned: [Self.unit])
            }
            let specs = [Self.running(.A, generation: 27), Self.running(.B, generation: 27), Self.running(.C, generation: 26)]
            let world = Self.world(specs, [.C: brain], ids: ["INV-L4"])
            // A moves the application twice (the second move knew the first) or B moves it at the same moment
            // (B did not know A's move).
            world.run([
                .moveApp27(mac: .A, bundle: "com.app.a", section: 1),
                .userEdit(mac: .C, unit: "ShowOnHover"),
                sameMac ? .moveApp27(mac: .A, bundle: "com.app.a", section: 2) : .moveApp27(mac: .B, bundle: "com.app.a", section: 2),
                .userEdit(mac: .C, unit: "UseIceBar"),
            ])
            return world
        }
        Oracles.check("INV-L4", bad: { world(second: Self.token3, sameMac: false) }, good: { world(second: Self.token3, sameMac: true) })
    }

    // MARK: INV-L5

    @Test("INV-L5 holds for the real engine and fails for an engine that decides by the clock")
    func l5() {
        let events: [SimEvent] = [
            .moveApp27(mac: .A, bundle: "com.app.a", section: 1), .advance(milliseconds: 6_000),
            .moveApp27(mac: .B, bundle: "com.app.a", section: 2), .advance(milliseconds: 30_000),
            .restartApp(mac: .A), .restartApp(mac: .B), .advance(milliseconds: 30_000),
            .moveApp27(mac: .A, bundle: "com.app.b", section: 1), .advance(milliseconds: 30_000),
            .restartApp(mac: .C), .advance(milliseconds: 30_000),
        ]
        let real = SimMetaSetup(seed: 5, preset: nil, macs: SimLayout27Tests.specs(), brainFactory: SimEngineTracerTests.redesignFactory)
        #expect(SimLayout27Oracles.relayIndependence(real, events).isEmpty)
        var caught = false
        for seed in UInt64(1)...40 where !caught {
            let clocked = SimMetaSetup(seed: seed, preset: nil, macs: SimLayout27Tests.specs(), brainFactory: { _, _ in LastWriterWinsByClock() })
            caught = !SimLayout27Oracles.relayIndependence(clocked, events, clockSeed: seed).isEmpty
        }
        #expect(caught, "an engine that decides by the clock passed INV-L5 on seeds 1 to 40")
    }

    // MARK: INV-L6

    @Test("INV-L6 fires when sync removes a value of the arrangement after an upgrade")
    func l6Removal() {
        func world(removing: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "C")
            brain.changedScript = { context, _ in
                if removing { SimUnits.set(SimLayout27OracleTests.unit, to: nil, in: &context.defaults) }
            }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.C, generation: 26)], [.C: brain], ids: ["INV-L6"])
            world.run([.upgradeOS(mac: .C), .launch(mac: .C), .moveApp27(mac: .C, bundle: "com.app.a", section: 1)])
            return world
        }
        Oracles.check("INV-L6", bad: { world(removing: true) }, good: { world(removing: false) })
    }

    @Test("INV-L6 fires when an upgraded Mac is asked about a unit its user did not change and that is no conflict")
    func l6Question() {
        func world(userChange: Bool) -> SimWorld {
            let brain = Self.asking(about: Self.unit, id: "C")
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.C, generation: 26)], [.C: brain], ids: ["INV-L6"])
            world.run([.upgradeOS(mac: .C), .launch(mac: .C)] + (userChange ? [.moveApp27(mac: .C, bundle: "com.app.a", section: 1)] : [.seed27(mac: .C)]))
            return world
        }
        Oracles.check("INV-L6", bad: { world(userChange: false) }, good: { world(userChange: true) })
    }

    // MARK: INV-K1

    @Test("INV-K1 fires when the known applications change outside launch and Restart, or lose an element")
    func k1() {
        func world(launchOnly: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.launchScript = { context, _ in
                if launchOnly { context.defaults["KnownApplications27"] = .array([.string("com.x")]) }
            }
            brain.changedScript = { context, _ in
                if !launchOnly { context.defaults["KnownApplications27"] = .array([.string("com.x")]) }
            }
            let world = Self.world([Self.running(.A, generation: 27)], [.A: brain], ids: ["INV-K1"])
            world.run([.placeNewApp27(mac: .A, bundle: "com.app.a")])
            return world
        }
        Oracles.check("INV-K1", bad: { world(launchOnly: false) }, good: { world(launchOnly: true) })
        // A launch that takes an element away is as wrong as a change in the middle of a session.
        var removing = SimScriptedBrain(id: "A")
        removing.launchScript = { context, brain in
            brain.counter += 1
            context.defaults["KnownApplications27"] = .array(brain.counter == 1 ? [.string("com.x")] : [])
        }
        let shrinking = Self.world([Self.running(.A, generation: 27)], [.A: removing], ids: ["INV-K1"])
        shrinking.run([.quit(mac: .A), .launch(mac: .A)])
        #expect(Oracles.found(shrinking, "INV-K1"))
    }

    @Test("INV-K1 fires on a sheet about the known applications and on a macOS 26 Mac whose set sync changes")
    func k1Sheet() {
        func world(about unit: String) -> SimWorld {
            let brain = Self.asking(about: unit, id: "A")
            let world = Self.world([Self.running(.A, generation: 27)], [.A: brain], ids: ["INV-K1"])
            world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
            return world
        }
        Oracles.check("INV-K1", bad: { world(about: SimUnits.known27) }, good: { world(about: "ShowOnHover") })
        func generation26(changing: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "B")
            brain.changedScript = { context, _ in
                if changing { context.defaults["KnownApplications27"] = .array([.string("com.x")]) }
            }
            let world = Self.world([Self.running(.A, generation: 27), Self.running(.B, generation: 26)], [.B: brain], ids: ["INV-K1"])
            world.step(.userEdit(mac: .B, unit: "ShowOnHover"))
            return world
        }
        Oracles.check("INV-K1", bad: { generation26(changing: true) }, good: { generation26(changing: false) })
    }

    // MARK: Automatic stores

    @Test("INV-A3 fires when a Mac publishes an automatic placement as its arrangement")
    func a3Publication() {
        func world(publishing: Bool) -> SimWorld {
            let brain = Self.publishing("A") { _ in
                // The file holds whatever tokens the Mac's settings hold: the engine under test copies them all.
                SimScriptedBrain.file(tokens: publishing ? ["auto-A-1"] : [Self.token1], mentioned: [Self.unit])
            }
            let world = Self.world([Self.running(.A, generation: 27)], [.A: brain], ids: ["INV-A3"])
            world.run([.seed27(mac: .A), .moveApp27(mac: .A, bundle: "com.app.a", section: 1)])
            return world
        }
        Oracles.check("INV-A3", bad: { world(publishing: true) }, good: { world(publishing: false) })
    }

    @Test("INV-A3 fires when an automatic event changes an arrangement the user made")
    func a3Overwrite() {
        // A brain whose own automatic stores overwrite the user's entry while seeding runs.
        func world(overwriting: Bool) -> SimWorld {
            let world = Self.world([Self.running(.A, generation: 27)], ids: ["INV-A3"])
            world.step(.moveApp27(mac: .A, bundle: "com.app.a", section: 1))
            if overwriting {
                // Forge the failure the oracle watches for: the entry the user made is gone after seeding.
                var brain = SimScriptedBrain(id: "A")
                brain.changedScript = { context, brain in
                    brain.counter += 1
                    if brain.counter == 2 { SimUnits.set(SimLayout27OracleTests.unit, to: nil, in: &context.defaults) }
                }
                let broken = Self.world([Self.running(.A, generation: 27)], [.A: brain], ids: ["INV-A3"])
                broken.step(.moveApp27(mac: .A, bundle: "com.app.a", section: 1))
                broken.step(.placeNewApp27(mac: .A, bundle: "com.app.b"))
                return broken
            }
            world.step(.placeNewApp27(mac: .A, bundle: "com.app.b"))
            return world
        }
        Oracles.check("INV-A3", bad: { world(overwriting: true) }, good: { world(overwriting: false) })
    }
}
