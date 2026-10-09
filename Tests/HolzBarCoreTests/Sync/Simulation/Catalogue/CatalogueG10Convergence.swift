//
//  CatalogueG10Convergence.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G10 of the A1 regression catalogue (S-68 to S-70): convergence and how often holzBar asks. These guard against "safe by
/// stalling" and "safe by asking": the Macs must end with the same state, and nobody is asked when nothing of theirs is
/// missing.
nonisolated enum CatalogueG10Convergence {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = [s68]
        all += s69
        all.append(s70)
        return all
    }()

    // MARK: S-68

    // S-68 · A closed laptop catches up · A1 G10 · class: pass · source: R3 non-fix note (must not ask).
    static let s68 = CatalogueScenario(id: "S-68", title: "A Mac that was offline while another wrote twice applies the latest without a question", source: .a1, kind: .pass) {
        func twoWrites(_ name: String) -> SimScenario {
            Catalogue.scenario(name, macs: CatalogueG1Joining.pairSpecs())
                .settle()
                .offline(.A, seconds: 7_200)
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 60)
                .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 60)
                .edit(.B, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
                .advance(seconds: 60)
        }
        // A is running: it applies the latest through Restart.
        let running = twoWrites("S-68 running")
            .online(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectHint(.A, present: true)
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 3)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        // A is closed: it applies the latest silently at launch.
        let closed = twoWrites("S-68 closed")
            .quit(.A)
            .online(.A)
            .settle()
            .launch(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 3)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectSilent()
            .expectQuiet()
        return Catalogue.combine("S-68", [running, closed].map(Catalogue.run))
    }

    // MARK: S-69

    // S-69 · An arrangement held only as a copy stalls · A1 G10 · class: scope · source: R5/R6 accepted risk (RC-5, RC-4).
    static let s69: [CatalogueScenario] = [
        CatalogueScenario(id: "S-69/26", title: "Settings converge and no Mac's arrangement is involved (generation 26)", source: .a1, kind: .scope) {
            runS69(generation: 26)
        },
        CatalogueScenario(id: "S-69/27", title: "An arrangement that exists only as relayed entries is applied by every Mac (generation 27)", source: .a1, kind: .scope) {
            runS69(generation: 27)
        },
    ]

    private static func runS69(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        let unit = generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry
        /// What every form ends with: the settings agree, nobody was asked about an arrangement, and in the generation-27
        /// form every Mac holds the newest arrangement without another rearrangement.
        func converged(_ scenario: SimScenario, drags: [SimMacName: Int] = [:]) -> SimScenarioResult {
            var ended = CatalogueG3Generations.common(scenario.relaunchAll(), generation: generation, drags: generation == 26 ? drags : [:])
            if generation == 27 {
                ended = CatalogueG6FileFaults.everyMacHolds(ended, unit, arrangement, label: "every Mac holds the newest arrangement")
            }
            return Catalogue.run(ended.expectQuiet())
        }
        // 1. The arrangement exists only in the file of a Mac of the other macOS version, which relays it: its writer is
        // gone and a Mac that joins later finds nothing else.
        let macs = [
            SimMacSpec(.B, .redesign, generation: generation, running: true),
            SimMacSpec(.C, .redesign, generation: 26, running: true),
            SimMacSpec(.D, .redesign, generation: generation, enabled: false, folder: nil, running: true, syncedFolder: "F1"),
        ]
        var relayed = Catalogue.scenario("S-69 relayed", macs: macs).settle()
        relayed = CatalogueG3Generations.arrange(relayed, .B, generation: generation, section: 1, k: 1)
            .edit(.B, Catalogue.hover, value: Catalogue.user(4, Catalogue.hover))
            .settle()
        relayed = CatalogueG6FileFaults.note(relayed, .B, unit, in: arrangement)
            .deleteFile(of: .B)
            .quit(.B)
            .settle()
            .turnOn(.D)
            .settle()
            .restartApp(.D)
            .settle()
            .expectUser(.D, Catalogue.hover, 4)
            .expectPrompts(count: 0)
        if generation == 27 {
            relayed = CatalogueG6FileFaults.everyMacHolds(relayed, unit, arrangement, label: "D holds B's arrangement without another rearrangement")
        } else {
            // The arrangement is B's own and never part of the copy: D holds none of it.
            relayed = relayed.expect("no Mac of the group holds B's arrangement but B") { world in
                [SimMacName.C, .D].allSatisfy { Catalogue.value(world, $0, unit) == nil } ? nil : "another Mac holds B's arrangement"
            }
        }
        var results = [Catalogue.run(CatalogueG3Generations.common(relayed, generation: generation, drags: [:]))]
        // 2. An older version of the Mac's file is restored while a newer one was read by another Mac.
        let marked = CatalogueBox(-1)
        var restored = Catalogue.scenario("S-69 restored", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
            .edit(.B, Catalogue.rehide, value: Catalogue.user(7, Catalogue.rehide))
            .settle()
        restored = CatalogueG3Generations.arrange(restored, .B, generation: generation, section: 1, k: 1).settle()
            .markFile(of: .B, in: marked)
        restored = CatalogueG3Generations.arrange(restored, .B, generation: generation, section: 2, k: 2).settle()
        restored = CatalogueG6FileFaults.note(restored, .B, unit, in: arrangement)
            .restoreFile(of: .B, to: marked)
            .settle()
            .restartApp(.A)
            .settle()
        results.append(converged(restored, drags: [.B: 2]))
        // 3. Keep is answered while the file is missing.
        let kept = CatalogueG6FileFaults.askedWorld("S-69 kept", generation: generation, arrangement: arrangement)
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .answer(.A, .keep)
            .settle()
        results.append(converged(kept, drags: [.B: 1]))
        return Catalogue.combine("S-69", results)
    }

    // MARK: S-70

    // S-70 · Extra questions after bookkeeping gaps · A1 G10 · class: pass · source: R5/R6 known risks (RC-5, RC-2).
    static let s70 = CatalogueScenario(id: "S-70", title: "No question after a bookkeeping gap when none of this Mac's changes is missing", source: .a1, kind: .pass) {
        let pair = CatalogueG1Joining.pairSpecs()
        /// Every case ends with nobody asked and the Macs holding the same settings.
        func asksNothing(_ scenario: SimScenario) -> SimScenarioResult {
            Catalogue.run(
                scenario.relaunchAll()
                    .expectPrompts(count: 0)
                    .expectUser(.A, Catalogue.hover, 1)
                    .expectUser(.B, Catalogue.hover, 1)
                    .expectQuiet()
            )
        }
        // 1. An adoption that moves nothing of this Mac's, then a version that holds this Mac's settings but no write of its own.
        let adoption = Catalogue.scenario(
            "S-70 adoption",
            macs: [
                SimMacSpec(.A, .redesign, generation: 26, running: true),
                SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, syncedFolder: "F1"),
            ]
        )
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .turnOn(.B)
            .settle()
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restartApp(.B)
            .settle()
            .edit(.A, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
            .settle()
            .restartApp(.B)
            .settle()
        // 2. A newer version that changed nothing, then a write over a missing file.
        let nothingChanged = Catalogue.scenario("S-70 newer version that changed nothing", macs: pair)
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .settle()
            .edit(.B, Catalogue.hover, value: Catalogue.user(5, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
        // 3. The state of an older build: A's state goes back to what it was at its launch.
        let olderState = Catalogue.scenario("S-70 older state", macs: pair)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .restartApp(.A)
            .edit(.A, Catalogue.spacing, value: Catalogue.user(4, Catalogue.spacing))
            .settle()
            .restoreSigma(.A)
            .launch(.A)
            .settle()
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .settle()
        // 4. More than 64 Macs in the record: C re-identifies again and again, and each identity keeps its file.
        var many = Catalogue.scenario(
            "S-70 seventy Macs",
            macs: pair + [SimMacSpec(.C, .redesign, generation: 26, running: true)]
        )
            .settle()
        for round in 0..<70 {
            many = many.reinstall(.C).launch(.C).turnOn(.C).advance(seconds: round.isMultiple(of: 10) ? 30 : 5)
        }
        many = many
            .settle()
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .settle()
        // 5. A clock set back after a reset.
        let clock = Catalogue.scenario("S-70 clock set back", macs: pair)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .sigmaLost(.A)
            .launch(.A)
            .settle()
            .clockStep(.A, milliseconds: -3_600_000)
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .settle()
        var results = [adoption, nothingChanged, olderState].map(asksNothing)
        // The seventy-Macs case and the clock case run with equal settings on both Macs once the change has arrived;
        // nobody may have been asked on the way.
        results.append(asksNothing(many))
        results.append(asksNothing(clock.edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover)).settle()))
        return Catalogue.combine("S-70", results)
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-68": CatalogueText(
            setup: "A and B on N.",
            steps: "A is closed and offline while B writes twice, with separate changes. Then A opens.",
            wrong: "A design with a single parent digest asked, because B's second version did not follow the one A had.",
            must: "A applies B's latest version without a question: silently at launch, or through Restart while running."
        ),
        "S-69": CatalogueText(
            setup: "An arrangement exists in the folder only as a copy: a sync app restored an older version, a Mac wrote over a deleted file while a kept layout waited, a Mac of the other macOS version set up the folder, or Keep was answered while the file was missing.",
            steps: "The Macs relaunch.",
            wrong: "No Mac takes the arrangement until the user rearranges on a Mac of that macOS version. Meanwhile each Mac keeps its own, so the Macs diverge with no end.",
            must: "The Macs converge on the newest user arrangement without another rearrangement (INV-15)."
        ),
        "S-70": CatalogueText(
            setup: "A and B on N. An adoption that does not move the last write; a newer version that changed nothing; the state of an older build; more than 64 Macs in the record; a clock set back after a reset.",
            steps: "A version arrives, or a write goes over a missing file.",
            wrong: "One extra question in each case.",
            must: "No question when none of this Mac's user changes is missing (INV-7)."
        ),
    ]
}

/// The G10 scenarios, one test each.
@Suite("CatalogueG10Convergence")
struct CatalogueG10ConvergenceTests {
    @Test("A1 G10: convergence and how often holzBar asks", arguments: CatalogueG10Convergence.scenarios)
    func scenario(_ scenario: CatalogueScenario) async {
        await HeavyTestGate.run {
            Catalogue.check(scenario)
        }
    }
}
