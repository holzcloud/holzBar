//
//  SimulationTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Gate G1, the exploration of the real engine (plan 28-13, analysis sections 5.4 to 5.9): seeded random runs per provider
/// preset against redesigned Macs of both generations, a skewed build, a 0.0.7-beta1 and a 0.0.7-beta2 peer; the same seed
/// giving the same trace; every deliberately weakened engine caught; and the metamorphic pairs over the same traces. The
/// budget comes from `SYNC_SIM_SEEDS` and `SYNC_SIM_STEPS` (small defaults in CI, 10,000 seeds at the gate).
@Suite("Simulation")
struct SimulationTests {
    // MARK: Seeded runs

    @Test("Seeded runs of the real engine end with no oracle violation, with the drain's agreement, quiescence and progress", arguments: SimSeedBlock.blocks(count: SimBudget.read().seeds))
    func seededRuns(block: SimSeedBlock) async {
        await HeavyTestGate.run {
            let budget = SimBudget.read()
            var runs = 0
            for seed in block.seeds {
                let result = SimExploration.run(seed: seed, preset: block.preset, steps: budget.steps, evidenceLoss: block.family.drawsEvidenceLoss)
                runs += 1
                let violations = SimExploration.violations(in: result.world, family: block.family)
                if let violation = violations.first {
                    let failure = SimExploration.shrunkFailure(seed: seed, preset: block.preset, macs: result.macs, events: result.events, violation: violation)
                    Issue.record(Comment(rawValue: "seed \(seed) of \(block.preset.rawValue) (\(block.family.rawValue) worlds): \(SimExploration.summary(violations))\n\n\(SimExploration.text(of: failure))"))
                    return
                }
            }
            SimGateReport.record("seeds \(block.preset.rawValue) \(runs) steps \(budget.steps) \(block.family.rawValue)")
        }
    }

    // MARK: Determinism

    @Test("The same seed gives the same trace hash on every run, and another seed gives another one", arguments: SimProviderPreset.allCases)
    func determinism(preset: SimProviderPreset) async {
        await HeavyTestGate.run {
            let budget = SimBudget.read()
            let first = SimSeedBlock.firstSeed
            var hashes: [UInt64: String] = [:]
            for seed in first..<(first + 10) {
                let one = SimExploration.run(seed: seed, preset: preset, steps: min(budget.steps, 60)).world.traceHash
                let two = SimExploration.run(seed: seed, preset: preset, steps: min(budget.steps, 60)).world.traceHash
                #expect(one == two, "seed \(seed) of \(preset.rawValue) gave two traces")
                hashes[seed] = one
                SimGateReport.record("hash \(preset.rawValue) \(seed) \(one)")
            }
            #expect(Set(hashes.values).count == hashes.count, "two seeds of \(preset.rawValue) gave one trace")
        }
    }

    // MARK: Control engines

    /// The first seed of 1 through 200 on which `scenario` shows the violation `caughtBy` asks for, or `nil`.
    private func firstCatch(_ scenario: (UInt64) -> [String]) -> UInt64? {
        for seed in UInt64(1)...200 where !scenario(seed).isEmpty { return seed }
        return nil
    }

    @Test("All six control engines are caught within their seed bounds, and the unmodified engine passes the same seeds")
    func controlEnginesAreCaught() async {
        await HeavyTestGate.run {
            var caught: [String: UInt64] = [:]

            // Last writer wins by clock, and the shared file written beta1-style: the generic scenarios of plan 28-06.
            let lastWriter = firstCatch { seed in
                let events = SimControlEngineTests.events(seed: seed)
                let world = SimControlEngineTests.run(seed: seed, events: events, factory: SimControlEngineTests.lastWriterFactory)
                return world.oracleViolations.filter { $0.id == "INV-S1" }.map(\.description)
            }
            caught["last writer wins by clock"] = lastWriter

            let sharedMacs = [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, running: true, clockOffsetMilliseconds: SimControlEngineTests.hour)]
            let shared = firstCatch { seed in
                var config = SimGenerator.Config(macs: sharedMacs, preset: .iCloud, steps: 60)
                config.identityEvents = false
                let events = SimGenerator.events(seed: seed, config)
                let world = SimControlEngineTests.run(seed: seed, events: events, macs: sharedMacs, preset: .iCloud, factory: { _, _ in SharedFileBeta1StyleEngine() })
                return world.oracleViolations.filter { $0.id == "INV-S1" || $0.id == "INV-S6" }.map(\.description)
            }
            caught["shared file written beta1-style"] = shared

            // The four weakened copies of the real engine.
            func variant<V: SimEngineVariant>(_ type: V.Type, _ name: String) {
                caught[name] = SimEngineVariantTests.catching(type)?.seed
                SimEngineVariantTests.survives(type)
            }
            variant(NoAppliedContext.self, "no applied-context rule")
            variant(UnreadOwnFileOverwrite.self, "overwriting an unread own file")
            variant(MintAtLaunchUntrusted.self, "minting at launch for an untrusted state")
            variant(EqualToDefaultAsUnset.self, "equal-to-default as unset")

            for name in caught.keys.sorted() {
                if let seed = caught[name] {
                    SimGateReport.record("control \(name) caught at seed \(seed)")
                } else {
                    Issue.record(Comment(rawValue: "the control engine \"\(name)\" survived seeds 1 through 200"))
                }
            }
            #expect(caught.count == 6)

            // The real engine on the generic scenarios, with every safety oracle.
            for seed in UInt64(1)...30 {
                // holzBar never changes a synced setting by itself (D-04), which the clock-driven scenarios of the control
                // engines do with `autoPlace`: the real engine runs the user's events, the clock steps, the restarts and time.
                let events = SimControlEngineTests.events(seed: seed).filter { if case .autoPlace = $0 { false } else { true } }
                let world = SimControlEngineTests.run(seed: seed, events: events, factory: { _, _ in SimMacRedesign() })
                #expect(world.oracleViolations.isEmpty, "the real engine on the generic scenario of seed \(seed): \(SimExploration.summary(world.oracleViolations))")
            }
        }
    }

    // MARK: Metamorphic pairs

    @Test("The same trace under a change that must not matter decides the same: automatic events, clock offsets, dot-free launches", arguments: SimProviderPreset.allCases)
    func metamorphicPairs(preset: SimProviderPreset) async {
        await HeavyTestGate.run {
            let budget = SimBudget.read()
            let count = max(4, budget.seeds / 5)
            let first = SimSeedBlock.firstSeed
            var pairs = 0
            for seed in first..<(first + UInt64(count)) {
                let macs = SimExploration.mix(seed: seed)
                let events = SimExploration.events(seed: seed, preset: nil, macs: macs, steps: min(budget.steps, 50), quiet: true)
                let setup = SimMetaSetup(seed: seed, preset: preset, macs: macs, brainFactory: SimExploration.brain)
                var found = SimMetamorphic.automaticEventsInvisible(setup, events, insertionSeed: seed)
                found += SimMetamorphic.clockIndependence(setup, events, clockSeed: seed)
                let extras = macs.filter { $0.version == .beta2 || $0.version == .redesignSkew }.map(\.name)
                if !extras.isEmpty {
                    found += SimMetamorphic.launchesMintNothing(setup, events, launching: extras, insertionSeed: seed)
                }
                pairs += 1
                if let violation = found.first {
                    Issue.record(Comment(rawValue: "seed \(seed) of \(preset.rawValue): \(violation.id.rawValue): \(violation.description)"))
                    return
                }
            }
            SimGateReport.record("metamorphic \(preset.rawValue) \(pairs)")
        }
    }

    @Test("Permuted, duplicated and coalesced deliveries of the same writes end in the same state", arguments: SimProviderPreset.allCases)
    func deliveryPairs(preset: SimProviderPreset) async {
        await HeavyTestGate.run {
            let budget = SimBudget.read()
            let count = max(3, budget.seeds / 8)
            let first = SimSeedBlock.firstSeed
            for seed in first..<(first + UInt64(count)) {
                let macs = SimExploration.mix(seed: seed, allowing: [.redesign, .redesignSkew])
                let events = SimExploration.events(seed: seed, preset: nil, macs: macs, steps: min(budget.steps, 40), quiet: true)
                let setup = SimMetaSetup(seed: seed, preset: preset, macs: macs, brainFactory: SimExploration.brain)
                if let violation = SimMetamorphic.deliveryIndependence(setup, events).first {
                    Issue.record(Comment(rawValue: "seed \(seed) of \(preset.rawValue): \(violation.id.rawValue): \(violation.description)"))
                    return
                }
            }
        }
    }
}
