//
//  CatalogueG9Races.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G9 of the A1 regression catalogue (S-64 to S-67): timing races. The simulator runs one event at a time, so a race is a
/// sequence of events with virtual time between them: a drag and a Restart within the capture delay, an edit around the
/// 2 s capture timer and around a stalled provider, a change while a hint shows, automatic events inside the settle window
/// of a display change or a wake. Time is virtual, so these scenarios are exact and repeatable.
nonisolated enum CatalogueG9Races {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = []
        all += s64
        all += [s65, s66]
        all += s67
        return all
    }()

    /// The hint of a question, as the simulator words it.
    static let chooseHint = "Choose Settings"

    // MARK: S-64

    // S-64 · Restart within 1.5 s of a drag · A1 G9 · class: scope · source: V0-#4, step E (RC-9, RC-6).
    static let s64: [CatalogueScenario] = [
        CatalogueScenario(id: "S-64/26", title: "A drag and an immediate Restart touch no arrangement of the group (generation 26)", source: .a1, kind: .scope) {
            runS64(generation: 26)
        },
        CatalogueScenario(id: "S-64/27", title: "A drag counts before the Restart applies other changes (generation 27)", source: .a1, kind: .scope) {
            runS64(generation: 27)
        },
    ]

    private static func runS64(generation: Int) -> SimScenarioResult {
        let moved = CatalogueBox<SimValue?>(nil)
        let unit = generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry
        // B changes a setting and A shows Restart. On A, drag an item and click Restart within a second.
        var scenario = Catalogue.scenario("S-64", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .expectHint(.A, present: true)
        scenario = CatalogueG3Generations.arrange(scenario, .A, generation: generation, section: 3, k: 3)
            .advance(milliseconds: 800)
            .restartApp(.A)
            .settle()
        scenario = CatalogueG6FileFaults.note(scenario, .A, unit, in: moved)
            .expect("the drag is kept across the restart") { world in
                Catalogue.value(world, .A, unit) != nil ? nil : "A lost its drag"
            }
            .expectUser(.A, Catalogue.hover, 1)
        var results: [SimScenarioResult] = []
        if generation == 27 {
            // The drag is an entry before the restart applies the other changes: B takes it in and keeps nothing else.
            results.append(Catalogue.run(
                scenario
                    .expectHint(.B, present: true)
                    .restartApp(.B)
                    .settle()
                    .expect("B takes the drag in") { world in
                        Catalogue.value(world, .B, unit) == moved.value ? nil : "B holds \(Catalogue.value(world, .B, unit)?.canonical ?? "nothing")"
                    }
                    .expectNoLayoutQuestion()
                    .expectQuiet()
            ))
            // The other Mac moved the same application: A asks, and Keep then keeps the drag.
            var both = Catalogue.scenario("S-64 same application", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
                .moveApp27(.B, bundle: Catalogue.appA, section: 1)
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
            both = both
                .moveApp27(.A, bundle: Catalogue.appA, section: 3)
                .advance(milliseconds: 800)
                .restartApp(.A)
                .settle()
            let kept = CatalogueBox<SimValue?>(nil)
            both = CatalogueG6FileFaults.note(both, .A, unit, in: kept)
                .expect("A asks about the application both Macs moved") { world in
                    Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
                }
            both = CatalogueG7Answers.answer(CatalogueG7Answers.answer(both, .A, .keep), .B, .use).settle().relaunchAll()
            results.append(Catalogue.run(CatalogueG6FileFaults.everyMacHolds(both, unit, kept, label: "Keep kept the drag on both Macs").expectQuiet()))
        } else {
            results.append(Catalogue.run(CatalogueG3Generations.common(scenario.restartApp(.B).settle(), generation: generation, drags: [.A: 3]).expectQuiet()))
        }
        return Catalogue.combine("S-64", results)
    }

    // MARK: S-65

    // S-65 · An edit lands during an exchange · A1 G9 · class: pass · source: R2 issue 13 (RC-9).
    static let s65 = CatalogueScenario(id: "S-65", title: "An edit made during an exchange is never recorded as synced without being written", source: .a1, kind: .pass) {
        // The edit lands at every distance from the first one around the 2 s capture timer, and around a stalled provider.
        var results: [SimScenarioResult] = []
        for delay in [0, 500, 1_500, 1_999, 2_000, 2_001, 3_000] as [Int64] {
            for stalled in [false, true] {
                var scenario = Catalogue.scenario("S-65 \(delay) ms\(stalled ? " stalled" : "")", macs: CatalogueG1Joining.pairSpecs())
                    .settle()
                    .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                if stalled { scenario = scenario.provider(.stall(mac: .A, forMilliseconds: 3_000)) }
                scenario = scenario
                    .advance(milliseconds: delay)
                    .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                    .settle()
                    .expect("A's file lists the last value, and the edit is never recorded as synced unwritten") { world in
                        let listed = Catalogue.publishedEntries(world, .A, Catalogue.hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                        return listed == [Catalogue.user(2, Catalogue.hover)] ? nil : "A's file lists \(listed.map(\.canonical))"
                    }
                    .expectHint(.B, present: true)
                    .restartApp(.B)
                    .settle()
                    .expectUser(.B, Catalogue.hover, 2)
                    .expectUser(.A, Catalogue.hover, 2)
                    .expectQuiet()
                results.append(Catalogue.run(scenario))
            }
        }
        // A moves offline while the edit lands: the next exchange carries it.
        let offline = Catalogue.scenario("S-65 offline", macs: CatalogueG1Joining.pairSpecs())
            .settle()
            .offline(.A, seconds: 120)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 1)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 60)
            .online(.A)
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectQuiet()
        results.append(Catalogue.run(offline))
        return Catalogue.combine("S-65", results)
    }

    // MARK: S-66

    // S-66 · A hint built from a stale side · A1 G9 · class: pass · source: R3 f5895cb6 (RC-9).
    static let s66 = CatalogueScenario(id: "S-66", title: "The hint always reflects the committed state", source: .a1, kind: .pass) {
        let restart = CatalogueG8Automatic.restartHint
        // A shows Restart for B's change; a change on A while the exchange runs makes it a question, and an answer or a
        // superseded entry makes it go away; never the stale one.
        let toQuestion = Catalogue.scenario("S-66 to a question", macs: CatalogueG1Joining.pairSpecs())
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .expect("A shows Restart") { world in world.brains[.A]?.hint == restart ? nil : "A shows \(world.brains[.A]?.hint ?? "no hint")" }
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(milliseconds: 100)
            .advance(seconds: 5)
            .expect("A's hint became the question") { world in world.brains[.A]?.hint == chooseHint ? nil : "A shows \(world.brains[.A]?.hint ?? "no hint")" }
            .settle()
            .expect("A still shows the question, never the stale Restart") { world in world.brains[.A]?.hint == chooseHint ? nil : "A shows \(world.brains[.A]?.hint ?? "no hint")" }
        let answered = CatalogueG7Answers.answer(toQuestion, .A, .use).settle()
            .expect("the hint of the answered question is gone, or only Restart") { world in
                let hint = world.brains[.A]?.hint
                return hint == nil || hint == restart ? nil : "A shows \(hint ?? "")"
            }
            .relaunchAll()
            .expectUser(.A, Catalogue.hover, 1)
            .expectQuiet()
        // The other way: a question that B's later change supersedes becomes a Restart, not a stale question.
        let toRestart = Catalogue.scenario("S-66 to Restart", macs: CatalogueG1Joining.pairSpecs())
            .offline(.A, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .online(.A)
            .settle()
            .expect("A shows the question") { world in world.brains[.A]?.hint == chooseHint ? nil : "A shows \(world.brains[.A]?.hint ?? "no hint")" }
        let resolved = CatalogueG7Answers.answer(toRestart, .B, .keep).settle()
            .expect("A's hint reflects B's answer, not the question it had") { world in
                let hint = world.brains[.A]?.hint
                return hint != chooseHint || world.brains[.A]?.openPrompt != nil ? nil : "A shows a question that has no sheet"
            }
        return Catalogue.combine("S-66", [Catalogue.run(answered), Catalogue.run(resolved)])
    }

    // MARK: S-67

    // S-67 · Displacement and arrangement within the 2 s settle window · A1 G9 · class: scope · source: R4 residual (RC-6, RC-9).
    static let s67: [CatalogueScenario] = [
        CatalogueScenario(id: "S-67/26", title: "Displacement and a drag inside the settle window sync nothing (generation 26)", source: .a1, kind: .scope) {
            runS67(generation: 26)
        },
        CatalogueScenario(id: "S-67/27", title: "Automatic events inside the settle window mint nothing, the user's move is the only entry (generation 27)", source: .a1, kind: .scope) {
            runS67(generation: 27)
        },
    ]

    private static func runS67(generation: Int) -> SimScenarioResult {
        var scenario = Catalogue.scenario("S-67", macs: CatalogueG3Generations.specs([.A, .B], generation: generation)).settle()
        guard generation == 27 else {
            scenario = scenario
                .autoPlace(.A, Catalogue.sectionsEntry)
                .advance(milliseconds: 400)
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
                .advance(milliseconds: 400)
                .settle()
            return Catalogue.run(CatalogueG3Generations.common(scenario, generation: generation, drags: [.A: 1]).expectHint(.B, present: false).expectQuiet())
        }
        // A display change or a wake: macOS displaces items and holzBar restores and seeds by itself, while the user moves
        // one application, all within two seconds and with the bar unread.
        let moved = CatalogueBox<SimValue?>(nil)
        scenario = scenario
            .seed27(.A)
            .advance(milliseconds: 300)
            .placeNewApp27(.A, bundle: Catalogue.appB)
            .advance(milliseconds: 300)
            .moveApp27(.A, bundle: Catalogue.appA, section: 1)
            .advance(milliseconds: 300)
            .seed27(.A)
            .advance(milliseconds: 300)
            .applyProfile(.A, "p9", byUser: false)
            .settle()
        scenario = CatalogueG6FileFaults.note(scenario, .A, Catalogue.layoutA, in: moved)
            .expect("the user's one move is the only entry A minted") { world in
                let units = ([Catalogue.layoutA] + CatalogueG8Automatic.placed).filter { !CatalogueG6FileFaults.ownListed(world, .A, $0).isEmpty }
                return units == [Catalogue.layoutA] ? nil : "A's file carries entries of its own for \(units)"
            }
            .restartApp(.B)
            .settle()
            .expect("B takes the move in and nothing that was displaced") { world in
                let held = ([Catalogue.layoutB, "l27/com.app.c", "l27/com.app.d"]).filter { Catalogue.value(world, .B, $0) != nil }
                guard held.isEmpty else { return "B holds the displaced \(held)" }
                return Catalogue.value(world, .B, Catalogue.layoutA) == moved.value ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
            }
        return Catalogue.run(scenario.expectNoLayoutQuestion().relaunchAll().expectQuiet())
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-64": CatalogueText(
            setup: "A and B on N.",
            steps: "B changes a setting, and A shows Restart. On A, Command-drag an item and click Restart within about a second.",
            wrong: "The save waits 1.5 s, so the hint saw no edit. The restart applied B's version, the next launch restored the old section, and the drag was lost.",
            must: "The drag counts, so A asks, or A saves first. Keep then keeps the drag."
        ),
        "S-65": CatalogueText(
            setup: "A on N.",
            steps: "A user edit happens between building an exchange request and recording its result.",
            wrong: "The record used an edit count newer than the one the decision saw, so the edit was marked as synced although it was never written.",
            must: "An edit made during an exchange is never recorded as synced, and it starts the next exchange."
        ),
        "S-66": CatalogueText(
            setup: "A and B on N.",
            steps: "A change happens while an exchange runs.",
            wrong: "The hint was built from the request's state, so it was stale: Restart instead of Choose Settings…, or the other way round.",
            must: "Hints always reflect the current local state."
        ),
        "S-67": CatalogueText(
            setup: "A and B on N.",
            steps: "macOS displaces items, and the user arranges, both within 2 s of a display change or wake, while holzBar does not read the bar.",
            wrong: "Decided as before round 4, so the displacement can count as the user's.",
            must: "INV-4 holds inside the window as well. The design must not depend on a snapshot taken before the arrangement, which may not exist."
        ),
    ]
}

/// The G9 scenarios, one test each.
@Suite("CatalogueG9Races")
struct CatalogueG9RacesTests {
    @Test("A1 G9: timing races", arguments: CatalogueG9Races.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
