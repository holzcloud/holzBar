//
//  CatalogueG7Answers.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G7 of the A1 regression catalogue (S-45 to S-54): what an answer means. Every answer is driven through
/// `SimScenario.answer(_:)`, so the engine builds the question and the answer's transitions; the scenarios assert on the
/// rows the sheet showed and on the entries published, not only on final values. In every scenario the answer writes one
/// fresh entry per shown unit and supersedes exactly the shown dots (the answer oracles check the supersession).
///
/// The SCOPE scenarios run in two forms: generation 26 asserts that the arrangement keys are never involved, generation 27
/// asserts the arrangement rules of D-04 (an untouched or automatic arrangement never overwrites another Mac's newer intent;
/// a move of the same application before the other Mac's entries are taken in is a conflict question).
nonisolated enum CatalogueG7Answers {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = []
        all += s45
        all.append(s46)
        all += s47
        all += s48
        all += s49
        all += [s50]
        all += s51
        all += s52
        all += [s53, s54]
        return all
    }()

    // MARK: Building blocks

    /// Answers on a Mac only if it has a sheet open.
    static func answer(_ scenario: SimScenario, _ mac: SimMacName, _ choice: SimAnswer) -> SimScenario {
        scenario.perform("\(mac) answers \(choice.canonical) if asked") { world in
            if world.brains[mac]?.openPrompt != nil { world.step(.answer(mac: mac, choice)) }
            return []
        }
    }

    /// The answer wrote one fresh entry of its own for the unit, and exactly that entry is live in the Mac's replica.
    static func expectFreshAnswer(_ scenario: SimScenario, _ mac: SimMacName, _ unit: String, _ k: Int) -> SimScenario {
        scenario.expect("\(mac)'s answer left one fresh entry for \(unit)") { world in
            let live = Catalogue.live(world, mac, unit)
            guard live == [Catalogue.user(k, unit)] else { return "\(mac)'s replica holds \(live.map(\.canonical)) for \(unit)" }
            return CatalogueG6FileFaults.ownListed(world, mac, unit).count == 1 ? nil : "\(mac) published \(CatalogueG6FileFaults.ownListed(world, mac, unit).count) entries of its own for \(unit)"
        }
    }

    /// The sheet of the Mac showed exactly these units, and nothing else (Keep replaces only what the sheet showed).
    static func expectShown(_ scenario: SimScenario, _ mac: SimMacName, _ units: [String]) -> SimScenario {
        scenario.expect("\(mac)'s sheet showed \(units)") { world in
            let shown = Catalogue.shownUnits(world, mac)
            return Set(shown) == Set(units) ? nil : "\(mac)'s sheets showed \(shown)"
        }
    }

    /// A drag on a Mac in the form of its generation: a move in the Layout pane on 27, a change of `ItemSections` on 26.
    static func drag(_ scenario: SimScenario, _ mac: SimMacName, generation: Int, section: Int, k: Int) -> SimScenario {
        CatalogueG3Generations.arrange(scenario, mac, generation: generation, section: section, k: k)
    }

    /// Both forms of an id, as literal entries are written by the callers; the unit an arrangement lives in.
    static func unit(_ generation: Int) -> String { generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry }

    // MARK: S-45

    // S-45 · Keep writes an untouched layout over a newer arrangement · A1 G7 · class: scope · source: V0-#2, step C (RC-8, RC-6).
    static let s45: [CatalogueScenario] = [
        CatalogueScenario(id: "S-45/26", title: "Keep replaces only the units the sheet showed (generation 26)", source: .a1, kind: .scope) {
            runS45(generation: 26)
        },
        CatalogueScenario(id: "S-45/27", title: "Keep never writes an untouched layout over a newer arrangement (generation 27)", source: .a1, kind: .scope) {
            runS45(generation: 27)
        },
    ]

    private static func runS45(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        // 1. to 3. B drags and changes the setting, A changes it the other way without touching the arrangement and keeps its own.
        var base = CatalogueG6FileFaults.keptWorld("S-45", generation: generation, arrangement: arrangement)
        base = expectShown(base, .A, [Catalogue.hover])
        base = expectFreshAnswer(base, .A, Catalogue.hover, 2)
        if generation == 27 {
            // The answer takes B's arrangement in: A's untouched placement never replaces it.
            base = base.expect("A took B's newer entries in and kept nothing of its own placement") { world in
                Catalogue.value(world, .A, Catalogue.layoutA) == arrangement.value ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
            }
        }
        // 4. A restarts, and every Mac that shares an arrangement holds B's.
        var forms = [Catalogue.run(CatalogueG6FileFaults.keptEnd(base.restartApp(.A).settle(), generation: generation, arrangement: arrangement, drag: 1))]
        // Variant: A also moves the same application while its sheet is open. The sheet shows what it showed; the conflict
        // about the application returns as a question once the sheet is answered, and nothing is replaced before the user
        // answers that one too.
        var moved = CatalogueG6FileFaults.askedWorld("S-45 moved", generation: generation, arrangement: arrangement)
        moved = drag(moved, .A, generation: generation, section: 3, k: 3).settle()
        moved = expectShown(moved, .A, [Catalogue.hover]).answer(.A, .keep).settle()
        let movedEnd: SimScenario
        if generation == 27 {
            movedEnd = answer(
                moved
                    .expect("the conflict about the application both Macs moved returns as a question") { world in
                        Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
                    }
                    .expect("B keeps its arrangement until the question is answered") { world in
                        Catalogue.value(world, .B, Catalogue.layoutA) == arrangement.value ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
                    },
                .A, .keep
            )
            .settle()
        } else {
            movedEnd = moved.expectNoLayoutQuestion()
                .expectKey(.B, Catalogue.sections, .dictionary(["Visible": Catalogue.user(1, Catalogue.sectionsEntry)]))
        }
        forms.append(Catalogue.run(answer(movedEnd, .B, .use).settle().relaunchAll().expectUser(.B, Catalogue.hover, 2).expectUser(.A, Catalogue.hover, 2)))
        // Variant: a move on A after the answer is a newer change of an arrangement A took in; B keeps its own until its restart.
        let after = drag(CatalogueG6FileFaults.keptWorld("S-45 after", generation: generation, arrangement: arrangement), .A, generation: generation, section: 3, k: 3)
            .settle()
            .expectNoLayoutQuestion()
        if generation == 27 {
            forms.append(Catalogue.run(
                after
                    .expect("B keeps its arrangement until it restarts") { world in
                        Catalogue.value(world, .B, Catalogue.layoutA) == arrangement.value ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
                    }
                    .expectHint(.B, present: true)
                    .restartApp(.B)
                    .settle()
                    .expect("B takes A's newer move in") { world in
                        Catalogue.value(world, .B, Catalogue.layoutA) == Catalogue.value(world, .A, Catalogue.layoutA) ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
                    }
            ))
        } else {
            forms.append(Catalogue.run(after.expectKey(.B, Catalogue.sections, .dictionary(["Visible": Catalogue.user(1, Catalogue.sectionsEntry)]))))
        }
        return Catalogue.combine("S-45", forms)
    }

    // MARK: S-46

    // S-46 · A version arrives while the question is open · A1 G7 · class: pass · source: V1-#2, step K (RC-8, RC-1).
    static let s46 = CatalogueScenario(id: "S-46", title: "An entry that arrives while the question is open survives the answer", source: .a1, kind: .pass) {
        let scenario = Catalogue.scenario("S-46", macs: CatalogueG1Joining.pairSpecs())
            .offline(.A, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .online(.A)
            .settle()
            .expect("A's sheet is open") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
            // B changes another setting while the sheet is open, and it reaches A.
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .advance(seconds: 60)
            .expect("the sheet is still open") { world in world.brains[.A]?.openPrompt == nil ? "A's sheet closed" : nil }
            .answer(.A, .keep)
            .settle()
            .expectUser(.A, Catalogue.hover, 2)
            // The answer wrote over what was shown only: B's new entry was not shown, so it survives and comes back, taken
            // in with the answer (it conflicts with nothing) or offered as a hint.
            .expect("B's new entry survived the answer") { world in
                let live = Catalogue.live(world, .A, Catalogue.rehide)
                guard live == [Catalogue.user(3, Catalogue.rehide)] else { return "A's replica holds \(live.map(\.canonical)) for \(Catalogue.rehide)" }
                let taken = Catalogue.value(world, .A, Catalogue.rehide) == Catalogue.user(3, Catalogue.rehide)
                return taken || world.brains[.A]?.hint != nil ? nil : "A neither holds B's new entry nor shows a hint for it"
            }
        let answered = expectFreshAnswer(scenario, .A, Catalogue.hover, 2)
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.rehide, 3)
            .relaunchAll()
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.rehide, 3)
            .expectQuiet()
        return Catalogue.run(answered)
    }

    // MARK: S-47

    // S-47 · Keep, then sync turned off and on before the restart · A1 G7 · class: scope · source: V1-#0, step I (RC-8, RC-5).
    static let s47: [CatalogueScenario] = [
        CatalogueScenario(id: "S-47/26", title: "Keep, then off and on, touches no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS47(generation: 26)
        },
        CatalogueScenario(id: "S-47/27", title: "Keep, then off and on, never records an arrangement as taken in that A does not hold (generation 27)", source: .a1, kind: .scope) {
            runS47(generation: 27)
        },
    ]

    private static func runS47(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        // 2. A turns sync off and on without a restart.
        var rejoined = CatalogueG6FileFaults.keptWorld("S-47", generation: generation, arrangement: arrangement)
            .turnOff(.A)
            .settle()
            .turnOn(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 2)
        if generation == 27 {
            // What the re-join records as taken in is what A holds: B's arrangement, never a placement of A's own.
            rejoined = rejoined
                .expect("A holds B's arrangement, the one the re-join recorded as taken in") { world in
                    Catalogue.value(world, .A, Catalogue.layoutA) == arrangement.value ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
                .expect("B keeps its arrangement, with no hint about A's re-join") { world in
                    Catalogue.value(world, .B, Catalogue.layoutA) == arrangement.value && world.brains[.B]?.openPrompt == nil ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
                .expectNoLayoutQuestion()
        }
        // 3. A restarts, and 4. B is quit and reopened: every Mac that shares an arrangement holds B's.
        let restarted = CatalogueG6FileFaults.keptEnd(rejoined.restartApp(.A).settle(), generation: generation, arrangement: arrangement, drag: 1)
        return Catalogue.run(restarted)
    }

    // MARK: S-48

    // S-48 · Keep, a drag, then joining again · A1 G7 · class: scope · source: V2-#0, step Q (RC-8, RC-5).
    static let s48: [CatalogueScenario] = [
        CatalogueScenario(id: "S-48/26", title: "Keep, a drag and a re-join never ask about an arrangement (generation 26)", source: .a1, kind: .scope) {
            runS48(generation: 26)
        },
        CatalogueScenario(id: "S-48/27", title: "Keep, a drag and a re-join never overwrite B's arrangement silently (generation 27)", source: .a1, kind: .scope) {
            runS48(generation: 27)
        },
    ]

    private static func runS48(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        /// The world of S-45 steps 1 to 3, then the drag on A, then the way the re-join happens. A took B's arrangement in
        /// with its answer, so its drag is a newer change of it: the re-join joins it as such, and B, which keeps its
        /// arrangement while it runs, is told with a hint and takes the drag in at its restart.
        func world(_ name: String, rejoin: (SimScenario) -> SimScenario) -> SimScenario {
            var scenario = CatalogueG6FileFaults.keptWorld(name, generation: generation, arrangement: arrangement)
            scenario = rejoin(scenario)
            if generation == 27 {
                return scenario
                    .expectNoLayoutQuestion()
                    .expect("B keeps its arrangement until it restarts, and is told") { world in
                        guard Catalogue.value(world, .B, Catalogue.layoutA) == arrangement.value else {
                            return "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
                        }
                        return world.brains[.B]?.hint != nil ? nil : "B shows no hint"
                    }
            }
            return scenario.expectNoLayoutQuestion()
        }
        // The drag, then sync off and on.
        let dragThenOffOn = world("S-48 off and on") {
            drag($0, .A, generation: generation, section: 3, k: 3).settle().turnOff(.A).settle().turnOn(.A).settle()
        }
        // The drag, then the same folder chosen again with Change….
        let dragThenChange = world("S-48 change folder") {
            drag($0, .A, generation: generation, section: 3, k: 3).settle().changeFolder(.A, folder: "F1").settle()
        }
        // Sync off, then the drag, then sync on.
        let offDragOn = world("S-48 off, drag, on") {
            drag($0.turnOff(.A).settle(), .A, generation: generation, section: 3, k: 3).settle().turnOn(.A).settle()
        }
        var results = [dragThenOffOn, dragThenChange, offDragOn].map { scenario -> SimScenarioResult in
            // B restarts and takes A's drag in; every Mac ends with it.
            var ended = scenario.restartApp(.B).settle().relaunchAll()
            if generation == 27 {
                ended = ended.expect("every Mac holds A's drag, the newest arrangement") { world in
                    let held = Set([SimMacName.A, .B].compactMap { Catalogue.value(world, $0, Catalogue.layoutA) })
                    guard held.count == 1, case .dictionary(let entry)? = held.first else { return "the Macs hold \(held.map(\.canonical))" }
                    return entry["section"] == .int(3) ? nil : "the Macs hold \(held.map(\.canonical))"
                }
            }
            return Catalogue.run(ended.expectUser(.A, Catalogue.hover, 2).expectUser(.B, Catalogue.hover, 2))
        }
        if generation == 26 {
            results = Array(results.prefix(1))
        }
        return Catalogue.combine("S-48", results)
    }

    // MARK: S-49

    // S-49 · After Keep, pushes stop, or an ordinary change asks about this Mac's own write · A1 G7 · class: scope · source: V1-#7, step L (RC-8, RC-9).
    static let s49: [CatalogueScenario] = [
        CatalogueScenario(id: "S-49/26", title: "After Keep an ordinary change syncs and asks nothing (generation 26)", source: .a1, kind: .scope) {
            runS49(generation: 26)
        },
        CatalogueScenario(id: "S-49/27", title: "After Keep an ordinary change syncs, the hint stays Restart (generation 27)", source: .a1, kind: .scope) {
            runS49(generation: 27)
        },
    ]

    private static func runS49(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        // After Keep, without a restart, A toggles another setting.
        let toggled = CatalogueG6FileFaults.keptWorld("S-49", generation: generation, arrangement: arrangement)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(5, Catalogue.rehide))
            .settle()
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about nothing again, and its own write is no question") { world in
                world.brains[.A]?.openPrompt == nil ? nil : "A's sheet is open again"
            }
            .expect("the toggle syncs: B receives it") { world in
                Catalogue.live(world, .B, Catalogue.rehide) == [Catalogue.user(5, Catalogue.rehide)] ? nil : "B's replica holds \(Catalogue.live(world, .B, Catalogue.rehide).map(\.canonical))"
            }
            .expectHint(.B, present: true)
        // A quits and reopens: it keeps the toggle and the arrangement it took in.
        let reopened = CatalogueG6FileFaults.keptEnd(toggled.restartApp(.A).settle(), generation: generation, arrangement: arrangement, drag: 1)
            .expectUser(.A, Catalogue.rehide, 5)
            .expectUser(.B, Catalogue.rehide, 5)
        return Catalogue.run(reopened)
    }

    // MARK: S-50

    // S-50 · Keep for a re-joining Mac brings the question back · A1 G7 · class: pass · source: V4, step AH (RC-8).
    static let s50 = CatalogueScenario(id: "S-50", title: "One Keep settles a re-joining Mac's question", source: .a1, kind: .pass) {
        // The S-31 setup: A is off, both change the setting, A turns sync on and is asked.
        let macs = CatalogueG1Joining.pairSpecs()
        let scenario = Catalogue.scenario("S-50", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .settle()
            .turnOff(.A)
            .settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .settle()
            .turnOn(.A)
            .settle()
            .expect("A asks at the re-join") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
            .checkpoint()
            .answer(.A, .keep)
            .settle()
            .expect("one Keep settles the question") { world in world.brains[.A]?.openPrompt == nil ? nil : "A's sheet is open again" }
        let asked = CatalogueBox(0)
        let settled = expectFreshAnswer(scenario, .A, Catalogue.hover, 2)
            .perform("count the sheets") { world in asked.value = Catalogue.promptCount(world); return [] }
            .restartApp(.A)
            .settle()
            .expect("the same question never returns") { world in
                Catalogue.promptCount(world) == asked.value && world.brains[.A]?.openPrompt == nil ? nil : "A asked again"
            }
            .relaunchAll()
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectQuiet()
        return Catalogue.run(settled)
    }

    // MARK: S-51

    // S-51 · Keep over a restored older version lists its stale layout again · A1 G7 · class: scope · source: V5, step AK (RC-8, RC-2, RC-3).
    static let s51: [CatalogueScenario] = [
        CatalogueScenario(id: "S-51/26", title: "Keep over a restored older version touches no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS51(generation: 26)
        },
        CatalogueScenario(id: "S-51/27", title: "Keep over a restored older version never lists a stale arrangement (generation 27)", source: .a1, kind: .scope) {
            runS51(generation: 27)
        },
    ]

    private static func runS51(generation: Int) -> SimScenarioResult {
        let marked = CatalogueBox(-1)
        let arrangement = CatalogueBox<SimValue?>(nil)
        /// A, B and D; the copy of A's file is set aside, D drags and changes the setting while A changes it the other way,
        /// A and B restart with D's arrangement, and the copy is put back.
        func world(_ name: String) -> SimScenario {
            var scenario = Catalogue.scenario(name, macs: CatalogueG3Generations.specs([.A, .B, .D], generation: generation))
                .edit(.A, Catalogue.rehide, value: Catalogue.user(1, Catalogue.rehide))
                .settle()
                .markFile(of: .A, in: marked)
                .offline(.A, seconds: 3_600)
            scenario = drag(scenario, .D, generation: generation, section: 1, k: 1)
                .edit(.D, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                .advance(seconds: 30)
            return CatalogueG6FileFaults.note(scenario, .D, unit(generation), in: arrangement)
                .online(.A)
                .settle()
                .restartApp(.B)
                .settle()
                .restoreFile(of: .A, to: marked)
                .advance(seconds: 60)
                .expect("A is asked") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
        }
        func end(_ scenario: SimScenario) -> SimScenarioResult {
            var ended = CatalogueG3Generations.common(
                answer(scenario, .A, .keep).settle().restartApp(.D).restartApp(.B).relaunchAll(),
                generation: generation,
                drags: generation == 26 ? [.D: 1] : [:]
            )
            .expectUser(.A, Catalogue.hover, 2)
            if generation == 27 {
                ended = CatalogueG6FileFaults.everyMacHolds(ended, Catalogue.layoutA, arrangement, label: "A, B and D keep D's arrangement")
                    .expect("A never lists a stale arrangement") { world in
                        let listed = Catalogue.publishedEntries(world, .A, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                        return listed.allSatisfy { $0 == arrangement.value } ? nil : "A's file lists \(listed.map(\.canonical))"
                    }
            }
            return Catalogue.run(ended.expectQuiet())
        }
        // The re-join path: A turns sync off and on before it answers, and is asked again.
        let rejoin = world("S-51 re-join").turnOff(.A).settle().turnOn(.A).settle()
        return Catalogue.combine("S-51", [end(world("S-51")), end(rejoin)])
    }

    // MARK: S-52

    // S-52 · Keep after a lost write: the arrangement is lost whichever button the user picks · A1 G7 · class: scope · source: V5, step AL (RC-8, RC-1).
    static let s52: [CatalogueScenario] = [
        CatalogueScenario(id: "S-52/26", title: "Keep after a lost write touches no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS52(generation: 26)
        },
        CatalogueScenario(id: "S-52/27", title: "Keep after a lost write keeps A's arrangement whichever button is pressed (generation 27)", source: .a1, kind: .scope) {
            runS52(generation: 27)
        },
    ]

    private static func runS52(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        /// A drags and changes the setting; before B reads it the file is deleted; B changes the setting; both ask.
        func world(_ name: String) -> SimScenario {
            var scenario = Catalogue.scenario(name, macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
                .settle()
                .offline(.B, seconds: 3_600)
            scenario = drag(scenario, .A, generation: generation, section: 1, k: 1)
                .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                .advance(seconds: 30)
            return CatalogueG6FileFaults.note(scenario, .A, unit(generation), in: arrangement)
                .provider(.deleteFolder())
                .advance(seconds: 30)
                .online(.B)
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
        }
        func end(_ scenario: SimScenario) -> SimScenarioResult {
            var ended = CatalogueG3Generations.common(
                answer(scenario, .B, .use).settle().relaunchAll(),
                generation: generation,
                drags: generation == 26 ? [.A: 1] : [:]
            )
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.hover, 2)
            if generation == 27 {
                ended = CatalogueG6FileFaults.everyMacHolds(ended, Catalogue.layoutA, arrangement, label: "B shows A's arrangement after its restart")
            }
            return Catalogue.run(ended.expectQuiet())
        }
        // Keep on A. The user's choice replaces B's setting, never A's arrangement.
        let keep = answer(world("S-52 Keep"), .A, .keep).settle()
        // Use on A would have taken B's setting; the arrangement is still A's, because B's version carries no arrangement.
        let use = answer(world("S-52 Use"), .A, .use).settle()
        let keepResult = end(keep.expect("A answered") { world in world.brains[.A]?.openPrompt == nil ? nil : "A's sheet is open" })
        var useEnded = CatalogueG3Generations.common(
            answer(use, .B, .use).settle().relaunchAll(),
            generation: generation,
            drags: generation == 26 ? [.A: 1] : [:]
        )
        if generation == 27 {
            useEnded = CatalogueG6FileFaults.everyMacHolds(useEnded, Catalogue.layoutA, arrangement, label: "Use does not lose A's arrangement either")
        }
        return Catalogue.combine("S-52", [keepResult, Catalogue.run(useEnded.expectUser(.A, Catalogue.hover, 1).expectUser(.B, Catalogue.hover, 1))])
    }

    // MARK: S-53

    // S-53 · Keep answered while the file is missing · A1 G7 · class: pass · source: V5, step AO (RC-8, RC-3).
    static let s53 = CatalogueScenario(id: "S-53", title: "Keep answered while the file is missing leaves B with Restart, not the same question", source: .a1, kind: .pass) {
        let arrangement = CatalogueBox<SimValue?>(nil)
        // B drags and changes a setting, A changes it too and is asked; the file is deleted and A chooses Keep.
        var scenario = Catalogue.scenario("S-53", macs: CatalogueG3Generations.specs([.A, .B], generation: 27))
            .settle()
            .offline(.A, seconds: 3_600)
        scenario = CatalogueG3Generations.arrange(scenario, .B, generation: 27, section: 1, k: 1)
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 30)
        scenario = CatalogueG6FileFaults.note(scenario, .B, Catalogue.layoutA, in: arrangement)
            .online(.A)
            .settle()
            .expect("A is asked") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .answer(.A, .keep)
            .settle()
            // B checks: Restart, not the same question again.
            .expect("B shows Restart, not a question") { world in
                if world.brains[.B]?.openPrompt != nil { return "B is asked again: \(world.brains[.B]?.openPrompt?.shown.map(\.unit) ?? [])" }
                return world.brains[.B]?.hint != nil ? nil : "B shows no hint"
            }
        let ended = CatalogueG6FileFaults.everyMacHolds(scenario.restartApp(.B).relaunchAll(), Catalogue.layoutA, arrangement, label: "B keeps its arrangement")
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.hover, 2)
            .expectQuiet()
        return Catalogue.run(ended)
    }

    // MARK: S-54

    // S-54 · The kept-layout record is lost after a successful write · A1 G7 · class: pass · source: V3-#3, step AB (RC-9, RC-5) [§5.2 pair 5].
    static let s54 = CatalogueScenario(id: "S-54", title: "A lost local record after a successful write never causes an overwrite", source: .a1, kind: .pass) {
        let arrangement = CatalogueBox<SimValue?>(nil)
        /// A's Keep reaches the file, then the local record goes (state lost, own file present; or a crash before the
        /// state is stored), and A changes a user setting.
        func world(_ name: String, loss: (SimScenario) -> SimScenario) -> SimScenarioResult {
            let lost = loss(CatalogueG6FileFaults.askedWorld(name, generation: 27, arrangement: arrangement))
                .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
                .settle()
            let recovered = answer(lost, .A, .keep).settle()
            let ended = CatalogueG6FileFaults.everyMacHolds(recovered.restartApp(.A).relaunchAll(), Catalogue.layoutA, arrangement, label: "nobody lost B's arrangement")
                .expectUser(.B, Catalogue.rehide, 3)
                .expectUser(.A, Catalogue.rehide, 3)
                .expect("A never published an arrangement of its own over B's") { world in
                    let listed = Catalogue.publishedEntries(world, .A, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                    return listed.allSatisfy { $0 == arrangement.value } ? nil : "A's file lists \(listed.map(\.canonical))"
                }
                .expectQuiet()
            return Catalogue.run(ended)
        }
        // The state is lost after the answer reached the file: the Mac starts with its own file present and no record.
        let sigmaLost = world("S-54 state lost") {
            $0.answer(.A, .keep).settle().sigmaLost(.A).launch(.A).settle()
        }
        // The app dies between the write and the update of the state.
        let crashed = world("S-54 crash") {
            $0.answer(.A, .keep).crash(.A).launch(.A).settle()
        }
        // Sync is turned off while the exchange runs.
        let off = world("S-54 sync turned off") {
            $0.answer(.A, .keep).turnOff(.A).settle().turnOn(.A).settle()
        }
        return Catalogue.combine("S-54", [sigmaLost, crashed, off])
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-45": CatalogueText(
            setup: "A and B on N.",
            steps: "B Command-drags (L2) and changes \"Show on hover\". A, without touching the layout, changes it the other way and chooses Keep This Mac's Settings. A restarts, or Command-drags before restarting.",
            wrong: "Keep wrote A's untouched layout, which differed only by holzBar's placements, over L2. B lost its drag. The question had shown only the settings difference.",
            must: "The folder keeps L2 together with A's setting. A takes L2 in. A drag on A before then asks."
        ),
        "S-46": CatalogueText(
            setup: "Both Macs change \"Show on hover\" and A's sheet opens.",
            steps: "B changes another setting and it reaches A. On A, choose Keep.",
            wrong: "Keep wrote over B's new version, which nobody had asked about.",
            must: "B's new entry survives the answer and comes back as a hint, and nothing of it is lost."
        ),
        "S-47": CatalogueText(
            setup: "S-45 steps 1 to 3, without restarting.",
            steps: "On A, turn sync off and on. Restart A, or Command-drag before restarting. Quit and reopen B.",
            wrong: "The re-join recorded B's kept layout as synced without applying it, so A's next drag overwrote B's arrangement silently.",
            must: "A holds the arrangement the re-join recorded, and B keeps L2."
        ),
        "S-48": CatalogueText(
            setup: "S-45 steps 1 to 3.",
            steps: "A Command-drags. Turn sync off and on; variants: choose the same folder again with Change…, or turn sync off, drag, then turn sync on.",
            wrong: "The re-join wrote A's dragged layout over B's kept layout without asking.",
            must: "B keeps L2 until it restarts, and nothing is lost: the drag is a newer change, published and taken in."
        ),
        "S-49": CatalogueText(
            setup: "S-47 step 1 (Keep, no restart).",
            steps: "Toggle another setting on A. Then quit and reopen A.",
            wrong: "Pushes stopped, and the ordinary change turned into a question about A's own write.",
            must: "The toggle syncs and B receives it. At the relaunch A keeps the toggle."
        ),
        "S-50": CatalogueText(
            setup: "A turns sync off; both Macs change a setting; A turns sync on and is asked.",
            steps: "A chooses Keep This Mac's Settings.",
            wrong: "The re-join branch was checked before Keep, so nothing was written and the same question came back.",
            must: "One Keep settles the question."
        ),
        "S-51": CatalogueText(
            setup: "A, B and D on N.",
            steps: "D Command-drags; A and B restart with D's arrangement. A copy of A's file saved before is put back. A chooses Keep. Repeat with sync turned off and on on A before the answer.",
            wrong: "Keep over a version that was not newer than A's last sync listed its stale layout as current, and D's arrangement was reverted on every Mac.",
            must: "A keeps D's arrangement. D and B keep it."
        ),
        "S-52": CatalogueText(
            setup: "A and B on N.",
            steps: "A Command-drags. Before B reads it, the file is deleted. B changes \"Show on hover\". A chooses Keep.",
            wrong: "Keep, answering a version without A's last layout write, kept B's stale layout. Use would have lost A's arrangement too.",
            must: "A keeps its arrangement, and B shows it after a restart. B's setting is replaced by A's, because the user chose so after the question showed it."
        ),
        "S-53": CatalogueText(
            setup: "B Command-drags and changes a setting. A changes it too and is asked.",
            steps: "The file is deleted and A chooses Keep. B checks.",
            wrong: "The answered version was not recorded, so B asked the same question again.",
            must: "B shows Restart, not a question. After the restart B keeps its arrangement and has A's setting."
        ),
        "S-54": CatalogueText(
            setup: "A's write that keeps B's layout reaches the file, but the local record is lost: sync is turned off while the exchange runs, holzBar quits between the write and the state update, or the state is lost.",
            steps: "A then changes a user setting.",
            wrong: "With no kept record, A judged the version an old copy and wrote its own layout over B's. B applied it at launch.",
            must: "A never overwrites on the strength of a missing record. It recovers the record or asks."
        ),
    ]
}

/// The G7 scenarios, one test each.
@Suite("CatalogueG7Answers")
struct CatalogueG7AnswersTests {
    @Test("A1 G7: what an answer means", arguments: CatalogueG7Answers.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
