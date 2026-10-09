//
//  SimExhaustiveTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Gate G1, the bounded exhaustive exploration of the real engine (plan 28-13, analysis section 5.4): every sequence over a small
/// alphabet of events up to a depth, in worlds of two or three Macs, two settings with two values each, with visited-state hashing
/// that cuts a sequence that ends in a state already reached with as many steps left. The depth is `SYNC_SIM_DEPTH` (6 in CI, 8 at
/// the gate); `SYNC_SIM_RUNS` bounds the runs of one family, and when a level of the search is larger than what is left of it, the
/// level is sampled at an even stride instead of cut off, so every depth is visited.
@Suite("SimExhaustive")
struct SimExhaustiveTests {
    /// One family of the plan: the Macs, the provider, and the alphabet (given the paths of the Macs' own files).
    struct Family: Sendable, CustomTestStringConvertible {
        var name: String
        var macs: [SimMacSpec]
        var preset: SimProviderPreset?
        var alphabet: @Sendable (_ files: [SimMacName: String]) -> [SimEvent]

        var testDescription: String { name }
    }

    static let seed: UInt64 = 5
    static let first = "ShowOnHover"
    static let second = "RehideInterval"

    private static func answers(_ mac: SimMacName) -> [SimEvent] {
        [SimAnswer.use, .keep, .later, .cancel].map { .answer(mac: mac, $0) }
    }

    private static func edits(_ mac: SimMacName) -> [SimEvent] {
        [.userEdit(mac: mac, unit: first), .userEdit(mac: mac, unit: second)]
    }

    static let families: [Family] = [
        // 1. Edits and answers: Use, Keep, Later and Cancel on both Macs.
        Family(
            name: "edits and answers",
            macs: [SimMacSpec(.A, .redesign, generation: 27, running: true), SimMacSpec(.B, .redesign, generation: 26, running: true)],
            preset: nil
        ) { _ in
            edits(.A) + edits(.B) + answers(.A) + answers(.B) + [.restartApp(mac: .A), .restartApp(mac: .B), .advance(milliseconds: 10_000)]
        },
        // 2. Adds file events on a provider that delays: delivery (time), a deleted file, a restored one, an evicted one.
        Family(
            name: "file events",
            macs: [SimMacSpec(.A, .redesign, generation: 27, running: true), SimMacSpec(.B, .redesign, generation: 26, running: true)],
            preset: .iCloud
        ) { files in
            let own = files[.A] ?? ""
            return [
                .userEdit(mac: .A, unit: first), .userEdit(mac: .B, unit: first), .userEdit(mac: .B, unit: second),
                .restartApp(mac: .A), .restartApp(mac: .B), .advance(milliseconds: 10_000),
                .answer(mac: .A, .use), .answer(mac: .B, .keep),
                .provider(.delete(path: own)), .provider(.restore(path: own, version: 1)), .provider(.evict(path: own, mac: .B)),
            ]
        },
        // 3. Adds identity events: preferences restored, the clock stepped, an account copied, a crash.
        Family(
            name: "identity events",
            macs: [SimMacSpec(.A, .redesign, generation: 27, running: true), SimMacSpec(.B, .redesign, generation: 26, running: true)],
            preset: nil
        ) { files in
            [
                .userEdit(mac: .A, unit: first), .userEdit(mac: .B, unit: first), .restartApp(mac: .A), .restartApp(mac: .B),
                .advance(milliseconds: 10_000), .answer(mac: .A, .keep), .answer(mac: .B, .use),
                .restorePrefs(mac: .A), .clockStep(mac: .A, milliseconds: 3_600_000), .copyAccount(from: .A, to: .B), .crash(mac: .B),
                .provider(.evict(path: files[.B] ?? "", mac: .A)),
            ]
        },
        // 4. Adds a 0.0.7-beta1 Mac.
        Family(
            name: "a beta1 Mac",
            macs: [
                SimMacSpec(.A, .redesign, generation: 27, running: true), SimMacSpec(.B, .redesign, generation: 26, running: true),
                SimMacSpec(.C, .beta1, running: true),
            ],
            preset: nil
        ) { _ in
            [
                .userEdit(mac: .A, unit: first), .userEdit(mac: .B, unit: second), .userEdit(mac: .C, unit: first), .userEdit(mac: .C, unit: second),
                .restartApp(mac: .A), .restartApp(mac: .B), .restartApp(mac: .C), .advance(milliseconds: 10_000),
                .answer(mac: .A, .use), .answer(mac: .A, .keep), .answer(mac: .B, .use), .answer(mac: .B, .keep),
            ]
        },
        // 5. A generation-26 Mac and two generation-27 Macs with arrangement moves.
        Family(
            name: "arrangement moves",
            macs: [
                SimMacSpec(.A, .redesign, generation: 26, running: true), SimMacSpec(.B, .redesign, generation: 27, running: true),
                SimMacSpec(.C, .redesign, generation: 27, running: true),
            ],
            preset: nil
        ) { _ in
            [
                .moveApp27(mac: .B, bundle: "com.app.a", section: 1), .moveApp27(mac: .B, bundle: "com.app.a", section: 2),
                .moveApp27(mac: .C, bundle: "com.app.a", section: 0), .moveApp27(mac: .C, bundle: "com.app.b", section: 1),
                .userEdit(mac: .A, unit: first), .restartApp(mac: .A), .restartApp(mac: .B), .restartApp(mac: .C),
                .advance(milliseconds: 10_000), .answer(mac: .B, .use), .answer(mac: .C, .keep), .answer(mac: .C, .use),
            ]
        },
    ]

    /// The path of each Mac's own device file in the worlds of `seed`: the identity is drawn at the first launch, so it does not
    /// depend on the events.
    static func ownFiles(of macs: [SimMacSpec], preset: SimProviderPreset?) -> [SimMacName: String] {
        let probe = SimWorld(seed: seed, macs: macs, preset: preset, brainFactory: SimExploration.brain, oracles: .none)
        var files: [SimMacName: String] = [:]
        for spec in macs {
            if let id = SimMacRedesignProbe.id(of: probe, spec.name) { files[spec.name] = SimFolderIO.directory + "/\(id).plist" }
        }
        return files
    }

    @Test("Every sequence over the alphabet of the family, up to the depth, ends with no oracle violation", arguments: SimExhaustiveTests.families)
    func exhaustive(family: Family) async {
        await HeavyTestGate.run {
            let budget = SimBudget.read()
            let alphabet = family.alphabet(Self.ownFiles(of: family.macs, preset: family.preset))
            let result = SimRunner.run(
                seed: Self.seed, preset: family.preset, macs: family.macs, brainFactory: SimExploration.brain,
                mode: .exhaustive(depth: budget.depth, alphabet: alphabet), oracles: .safety, maximumRuns: budget.exhaustiveRuns
            )
            if let violation = result.violations.first {
                let failure = SimFailure(
                    name: "exhaustive \(family.name)", seed: Self.seed, preset: family.preset, macs: family.macs, events: result.events, violation: violation
                )
                Issue.record(Comment(rawValue: "\(family.name): \(SimExploration.summary(result.violations))\n\n\(SimExploration.text(of: failure))"))
                return
            }
            #expect(result.runs > alphabet.count, "\(family.name) explored only \(result.runs) runs")
            SimGateReport.record("exhaustive \(family.name) depth \(budget.depth) alphabet \(alphabet.count) runs \(result.runs) states \(result.visitedStates)")
        }
    }
}
