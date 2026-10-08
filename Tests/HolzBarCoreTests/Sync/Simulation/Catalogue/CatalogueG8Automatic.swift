//
//  CatalogueG8Automatic.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G8 of the A1 regression catalogue (S-55 to S-63): automatic versus user changes. What holzBar places, seeds, restores
/// or learns by itself is never a change of the user's: it creates no dot, no hint on another Mac and no question, and it
/// never replaces an arrangement the user made (decision D-04). The SCOPE scenarios run in two forms: generation 26
/// asserts that the arrangement keys are never involved, generation 27 asserts the arrangement rules with the simulator's
/// automatic events (`placeNewApp27`, `seed27`, `applyProfile(byUser: false)`) and the user's moves.
nonisolated enum CatalogueG8Automatic {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = [s55]
        all += s56
        all += s57
        all += s58
        all += s59
        all += s60
        all += s61
        all += s62
        all.append(s63)
        return all
    }()

    /// What a Mac shows for a change that waits (a Restart hint), as the simulator words it.
    static let restartHint = "Settings changed on another Mac"

    // MARK: Building blocks

    /// The units holzBar places or seeds by itself in the generation-27 forms.
    static let placed = [Catalogue.layoutB, "l27/com.app.c", "l27/com.app.d"]

    /// holzBar places a new item or application by itself: the default placement of an unsaved item on macOS 26 (a store of
    /// the local `ItemSections`), the placement and the seeding of applications on macOS 27.
    static func place(_ scenario: SimScenario, _ mac: SimMacName, generation: Int) -> SimScenario {
        generation == 27
            ? scenario.placeNewApp27(mac, bundle: Catalogue.appB).seed27(mac)
            : scenario.autoPlace(mac, Catalogue.sectionsEntry)
    }

    /// The Mac published no entry of its own for any unit holzBar placed.
    static func publishedNoPlacement(_ scenario: SimScenario, _ mac: SimMacName, extra: [String] = []) -> SimScenario {
        scenario.expect("\(mac) published no entry for what holzBar placed") { world in
            let listed = (placed + extra).filter { !CatalogueG6FileFaults.ownListed(world, mac, $0).isEmpty }
            return listed.isEmpty ? nil : "\(mac)'s file carries entries of its own for \(listed)"
        }
    }

    /// The Mac shows the Restart hint of a waiting change, and no question.
    static func expectRestart(_ scenario: SimScenario, _ mac: SimMacName) -> SimScenario {
        scenario.expect("\(mac) shows the Restart hint, no question") { world in
            let hint = world.brains[mac]?.hint
            return hint == restartHint && world.brains[mac]?.openPrompt == nil ? nil : "\(mac) shows \(hint ?? "no hint")"
        }
    }

    // MARK: S-55

    // S-55 · holzBar places new items or apps · A1 G8 · class: pass · source: SA-05 (must not ask).
    static let s55 = CatalogueScenario(id: "S-55", title: "What holzBar places by itself creates no dot, no hint and no question", source: .a1, kind: .pass) {
        var results: [SimScenarioResult] = []
        for generation in [26, 27] {
            let held = CatalogueBox<SimValue?>(nil)
            var scenario = Catalogue.scenario("S-55 generation \(generation)", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
                // A Restart hint is showing on A.
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
            scenario = expectRestart(scenario, .A)
            scenario = place(scenario, .A, generation: generation).settle()
            scenario = expectRestart(scenario, .A)
                .expectHint(.B, present: false)
                .expectPrompts(count: 0)
                .expectNoLayoutQuestion()
            scenario = publishedNoPlacement(scenario, .A)
            if generation == 27 {
                // B arranges: A takes it in at its restart, keeps its own placement of the other application, and B never
                // gets A's placement.
                scenario = CatalogueG6FileFaults.note(scenario.moveApp27(.B, bundle: Catalogue.appA, section: 1).settle(), .B, Catalogue.layoutA, in: held)
                    .restartApp(.A)
                    .settle()
                    .expect("A holds B's arrangement of the application B moved") { world in
                        Catalogue.value(world, .A, Catalogue.layoutA) == held.value ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
                    }
                    .expect("A's placement of the other application stays A's") { world in
                        Catalogue.value(world, .A, Catalogue.layoutB) != nil && Catalogue.value(world, .B, Catalogue.layoutB) == nil
                            ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutB)?.canonical ?? "nothing"), B holds \(Catalogue.value(world, .B, Catalogue.layoutB)?.canonical ?? "nothing")"
                    }
            }
            results.append(Catalogue.run(scenario.relaunchAll().expectUser(.A, Catalogue.hover, 1).expectQuiet()))
        }
        return Catalogue.combine("S-55", results)
    }

    // MARK: S-56

    // S-56 · A Command-click without a move · A1 G8 · class: scope · source: V0-#6, V1-#3 (RC-6).
    static let s56: [CatalogueScenario] = [
        CatalogueScenario(id: "S-56/26", title: "A Command-click without a move is no edit (generation 26)", source: .a1, kind: .scope) {
            runS56(generation: 26)
        },
        CatalogueScenario(id: "S-56/27", title: "A Command-click without a move creates no intent (generation 27)", source: .a1, kind: .scope) {
            runS56(generation: 27)
        },
    ]

    private static func runS56(generation: Int) -> SimScenarioResult {
        // With Restart showing, the Command-click leaves holzBar's default placement of an unsaved item behind.
        var scenario = Catalogue.scenario("S-56", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
        scenario = place(scenario, .A, generation: generation).settle()
        scenario = expectRestart(scenario, .A)
            // The next push of A lists holzBar's placements as nobody's.
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
        scenario = publishedNoPlacement(expectRestart(scenario, .A), .A)
            .expectNoLayoutQuestion()
            .expect("B holds none of A's placements") { world in
                let held = (placed + [Catalogue.sectionsEntry]).filter { Catalogue.value(world, .B, $0) != nil }
                return held.isEmpty ? nil : "B holds \(held)"
            }
        return Catalogue.run(scenario.relaunchAll().expectUser(.B, Catalogue.rehide, 2).expectUser(.A, Catalogue.hover, 1).expectQuiet())
    }

    // MARK: S-57

    // S-57 · Applying the current profile again · A1 G8 · class: scope · source: V1-#4, macOS 27 (RC-6).
    static let s57: [CatalogueScenario] = [
        CatalogueScenario(id: "S-57/26", title: "Applying a profile again changes nothing (generation 26)", source: .a1, kind: .scope) {
            runS57(generation: 26)
        },
        CatalogueScenario(id: "S-57/27", title: "Applying the current profile again is no edit (generation 27)", source: .a1, kind: .scope) {
            runS57(generation: 27)
        },
    ]

    private static func runS57(generation: Int) -> SimScenarioResult {
        var scenario = Catalogue.scenario("S-57", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
        if generation == 27 {
            // A holds B's arrangement and has saved it as a profile.
            scenario = scenario.moveApp27(.B, bundle: Catalogue.appA, section: 1).settle().restartApp(.A).settle().saveProfile(.A, "p1").settle()
        }
        scenario = scenario
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
        scenario = expectRestart(scenario, .A)
            .checkpoint()
            // The hotkey applies the profile that is current already.
            .applyProfile(.A, "p1")
            .settle()
        scenario = expectRestart(scenario, .A)
            .expectNoWrite(.A)
            .expectNoLayoutQuestion()
            .expectPrompts(count: 0)
        return Catalogue.run(scenario.relaunchAll().expectUser(.A, Catalogue.hover, 1).expectQuiet())
    }

    // MARK: S-58

    // S-58 · The first move of an item holzBar never saved · A1 G8 · class: scope · source: V2-#4a, V3-#2a (RC-6) [§5.2 pair 7].
    static let s58: [CatalogueScenario] = [
        CatalogueScenario(id: "S-58/26", title: "The first move of an unsaved item is local and asks nothing (generation 26)", source: .a1, kind: .scope) {
            runS58(generation: 26)
        },
        CatalogueScenario(id: "S-58/27", title: "The first move of an application with no saved entry counts (generation 27)", source: .a1, kind: .scope) {
            runS58(generation: 27)
        },
    ]

    private static func runS58(generation: Int) -> SimScenarioResult {
        let macs = CatalogueG3Generations.specs([.A, .B], generation: generation)
        guard generation == 27 else {
            // Both Macs drag an item that has no saved section: the keys are local, nothing syncs, nothing is asked.
            let scenario = Catalogue.scenario("S-58 local", macs: macs)
                .offline(.A, seconds: 3_600)
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(2, Catalogue.sectionsEntry))
                .edit(.B, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
                .advance(seconds: 30)
                .online(.A)
                .settle()
            return Catalogue.run(CatalogueG3Generations.common(scenario, generation: generation, drags: [.A: 2, .B: 1]).expectPrompts(count: 0).expectQuiet())
        }
        // The user moves an application that has no saved entry: one explicit entry, which the other Mac takes in.
        let first = Catalogue.scenario("S-58 first move", macs: macs)
            .settle()
            .moveApp27(.A, bundle: Catalogue.appB, section: 2)
            .settle()
            .expect("A wrote the move as one explicit entry") { world in
                let listed = CatalogueG6FileFaults.ownListed(world, .A, Catalogue.layoutB)
                guard listed.count == 1, listed.first?.payload != .deleted else { return "A's file carries \(listed.count) entries of its own for \(Catalogue.layoutB)" }
                return nil
            }
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expect("B takes the move in") { world in
                Catalogue.value(world, .B, Catalogue.layoutB) == Catalogue.value(world, .A, Catalogue.layoutB) && Catalogue.value(world, .B, Catalogue.layoutB) != nil
                    ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutB)?.canonical ?? "nothing")"
            }
            .expectNoLayoutQuestion()
            .expectQuiet()
        // The other Mac moved the same application too: holzBar asks, and replaces nothing before the answer.
        let both = Catalogue.scenario("S-58 both moved", macs: macs)
            .settle()
            .offline(.A, seconds: 3_600)
            .moveApp27(.A, bundle: Catalogue.appB, section: 2)
            .moveApp27(.B, bundle: Catalogue.appB, section: 1)
            .advance(seconds: 30)
            .online(.A)
            .settle()
            .expect("holzBar asks about the application both Macs moved") { world in
                Catalogue.layoutQuestions(world).contains(Catalogue.layoutB) ? nil : "nobody asked about \(Catalogue.layoutB)"
            }
            .expect("each Mac keeps its own move until the answer") { world in
                let a = Catalogue.value(world, .A, Catalogue.layoutB)
                let b = Catalogue.value(world, .B, Catalogue.layoutB)
                return a != nil && b != nil && a != b ? nil : "A holds \(a?.canonical ?? "nothing"), B holds \(b?.canonical ?? "nothing")"
            }
        let answered = CatalogueG7Answers.answer(CatalogueG7Answers.answer(both, .A, .keep), .B, .use).settle().relaunchAll()
            .expect("both Macs hold A's move") { world in
                let a = Catalogue.value(world, .A, Catalogue.layoutB)
                return a != nil && a == Catalogue.value(world, .B, Catalogue.layoutB) ? nil : "A holds \(a?.canonical ?? "nothing"), B holds \(Catalogue.value(world, .B, Catalogue.layoutB)?.canonical ?? "nothing")"
            }
            .expectQuiet()
        return Catalogue.combine("S-58", [Catalogue.run(first), Catalogue.run(answered)])
    }

    // MARK: S-59

    // S-59 · macOS displaces items, then the user Command-clicks or drags · A1 G8 · class: scope · source: V2-#4b, V3-#2b (RC-6) [§5.2 pair 6].
    static let s59: [CatalogueScenario] = [
        CatalogueScenario(id: "S-59/26", title: "Displaced items keep their sections and nothing of them syncs (generation 26)", source: .a1, kind: .scope) {
            runS59(generation: 26)
        },
        CatalogueScenario(id: "S-59/27", title: "Displacement creates nothing, only the application the user moved counts (generation 27)", source: .a1, kind: .scope) {
            runS59(generation: 27)
        },
    ]

    private static func runS59(generation: Int) -> SimScenarioResult {
        let held = CatalogueBox<SimValue?>(nil)
        var scenario = Catalogue.scenario("S-59", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
        if generation == 27 {
            // B arranged one application and A holds it; then a display change displaces every cached item on A, and the
            // user moves one other application.
            scenario = CatalogueG6FileFaults.note(scenario.moveApp27(.B, bundle: Catalogue.appA, section: 1).settle(), .B, Catalogue.layoutA, in: held)
                .restartApp(.A)
                .settle()
                .seed27(.A)
                .placeNewApp27(.A, bundle: Catalogue.appB)
                .moveApp27(.A, bundle: Catalogue.appB, section: 2)
                .settle()
                .expect("A published the move and nothing else") { world in
                    let units = ([Catalogue.layoutA] + placed).filter { !CatalogueG6FileFaults.ownListed(world, .A, $0).isEmpty }
                    return units == [Catalogue.layoutB] ? nil : "A's file carries entries of its own for \(units)"
                }
                .restartApp(.B)
                .settle()
                .expect("B keeps its own arrangement and takes only the move in") { world in
                    guard Catalogue.value(world, .B, Catalogue.layoutA) == held.value else { return "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing") for \(Catalogue.layoutA)" }
                    guard Catalogue.value(world, .B, Catalogue.layoutB) == Catalogue.value(world, .A, Catalogue.layoutB) else { return "B lacks A's move" }
                    let seeded = placed.filter { $0 != Catalogue.layoutB }.filter { Catalogue.value(world, .B, $0) != nil }
                    return seeded.isEmpty ? nil : "B holds the displaced \(seeded)"
                }
        } else {
            scenario = scenario
                .edit(.B, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
                .autoPlace(.A, Catalogue.sectionsEntry)
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(2, Catalogue.sectionsEntry))
                .settle()
                .restartApp(.B)
                .settle()
            scenario = CatalogueG3Generations.common(scenario, generation: generation, drags: [.A: 2, .B: 1])
        }
        return Catalogue.run(scenario.expectNoLayoutQuestion().relaunchAll().expectQuiet())
    }

    // MARK: S-60

    // S-60 · A reconciliation stores an old section over the user's fresh save · A1 G8 · class: scope · source: V2-#7 (RC-6, RC-9).
    static let s60: [CatalogueScenario] = [
        CatalogueScenario(id: "S-60/26", title: "A stale store never replaces a saved section and syncs nothing (generation 26)", source: .a1, kind: .scope) {
            runS60(generation: 26)
        },
        CatalogueScenario(id: "S-60/27", title: "An automatic store never overwrites an entry with applied intent (generation 27)", source: .a1, kind: .scope) {
            runS60(generation: 27)
        },
    ]

    private static func runS60(generation: Int) -> SimScenarioResult {
        var scenario = Catalogue.scenario("S-60", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
        if generation == 27 {
            // A saves a profile of the old arrangement, then moves an application. A binding of the profile to a Space
            // applies it again by itself: it never replaces the move, which is the entry B takes in.
            scenario = scenario
                .moveApp27(.A, bundle: Catalogue.appA, section: 1)
                .saveProfile(.A, "p1")
                .settle()
                .moveApp27(.A, bundle: Catalogue.appA, section: 2)
                .settle()
            let moved = CatalogueBox<SimValue?>(nil)
            scenario = CatalogueG6FileFaults.note(scenario, .A, Catalogue.layoutA, in: moved)
                .applyProfile(.A, "p1", byUser: false)
                .settle()
                .expect("the automatic store never overwrote the move") { world in
                    Catalogue.value(world, .A, Catalogue.layoutA) == moved.value ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
                .restartApp(.B)
                .settle()
            scenario = CatalogueG6FileFaults.everyMacHolds(scenario, Catalogue.layoutA, moved, label: "B took the user's move in, never the stale store")
        } else {
            // The user saves a section by dragging; a reconciliation then stores the old section. The key never syncs.
            scenario = scenario
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
                .edit(.B, Catalogue.sectionsEntry, value: Catalogue.user(5, Catalogue.sectionsEntry))
                .settle()
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(2, Catalogue.sectionsEntry))
                .settle()
            scenario = CatalogueG3Generations.common(scenario, generation: generation, drags: [.A: 2, .B: 5])
        }
        return Catalogue.run(scenario.expectNoLayoutQuestion().relaunchAll().expectQuiet())
    }

    // MARK: S-61

    // S-61 · A move in the Layout pane during a restore · A1 G8 · class: scope · source: step AD (RC-6).
    static let s61: [CatalogueScenario] = [
        CatalogueScenario(id: "S-61/26", title: "A move during a restore is local and kept (generation 26)", source: .a1, kind: .scope) {
            runS61(generation: 26)
        },
        CatalogueScenario(id: "S-61/27", title: "A move during a restore is kept and synced (generation 27)", source: .a1, kind: .scope) {
            runS61(generation: 27)
        },
    ]

    private static func runS61(generation: Int) -> SimScenarioResult {
        let moved = CatalogueBox<SimValue?>(nil)
        var scenario = Catalogue.scenario("S-61", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
        if generation == 27 {
            // A wakes: holzBar restores and seeds by itself, and the user moves an application in the middle of it.
            scenario = scenario
                .seed27(.A)
                .advance(milliseconds: 300)
                .moveApp27(.A, bundle: Catalogue.appA, section: 1)
                .advance(milliseconds: 300)
                .seed27(.A)
                .placeNewApp27(.A, bundle: Catalogue.appB)
                .settle()
            scenario = CatalogueG6FileFaults.note(scenario, .A, Catalogue.layoutA, in: moved)
                .expectHint(.B, present: true)
                // The next restore never reverts it.
                .restartApp(.A)
                .settle()
                .restartApp(.B)
                .settle()
            scenario = CatalogueG6FileFaults.everyMacHolds(scenario, Catalogue.layoutA, moved, label: "the move was saved, synced and never reverted")
        } else {
            scenario = scenario
                .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
                .settle()
                .restartApp(.A)
                .settle()
            scenario = CatalogueG3Generations.common(scenario, generation: generation, drags: [.A: 1])
        }
        return Catalogue.run(scenario.expectNoLayoutQuestion().expectQuiet())
    }

    // MARK: S-62

    // S-62 · A layout rearranged during the beta2 pause, then sync resumes · A1 G8 · class: scope · source: 77ab5629 (RC-6, RC-7).
    static let s62: [CatalogueScenario] = [
        CatalogueScenario(id: "S-62/26", title: "An arrangement made during the pause is never part of a question (generation 26)", source: .a1, kind: .scope) {
            runS62(generation: 26)
        },
        CatalogueScenario(id: "S-62/27", title: "An arrangement made during the pause is the user's present value (generation 27)", source: .a1, kind: .scope) {
            runS62(generation: 27)
        },
    ]

    private static func runS62(generation: Int) -> SimScenarioResult {
        // A synced under beta1, then updated to beta2, which runs no migration and counts no edits; B runs the new build.
        let specs = [
            SimMacSpec(.A, .beta2, generation: generation, running: true),
            SimMacSpec(.B, .redesign, generation: generation, running: true),
        ]
        var scenario = Catalogue.scenario("S-62", macs: specs).settle()
        // 1. The user rearranges A's menu bar during the pause. B's arrangement differs.
        scenario = CatalogueG3Generations.arrange(scenario, .A, generation: generation, section: 3, k: 3)
        scenario = CatalogueG3Generations.arrange(scenario, .B, generation: generation, section: 1, k: 1).settle()
        let mine = CatalogueBox<SimValue?>(nil)
        scenario = CatalogueG6FileFaults.note(scenario, .A, generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry, in: mine)
            // 2. A updates to the new build and sync resumes.
            .updateApp(.A, .redesign)
            .launch(.A)
            .settle()
        if generation == 27 {
            scenario = scenario
                .expect("A asks about the arrangement where it differs from the group's") { world in
                    Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
                }
                .expect("A's arrangement is replaced by nothing before the answer") { world in
                    Catalogue.value(world, .A, Catalogue.layoutA) == mine.value ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
            scenario = CatalogueG7Answers.answer(scenario, .A, .keep).settle()
                .relaunchAll()
            scenario = CatalogueG6FileFaults.everyMacHolds(scenario, Catalogue.layoutA, mine, label: "the arrangement the user made is the group's after Keep")
        } else {
            scenario = CatalogueG3Generations.common(scenario.relaunchAll(), generation: generation, drags: [.A: 3, .B: 1])
                .expectPrompts(count: 0)
        }
        return Catalogue.run(scenario)
    }

    // MARK: S-63

    // S-63 · Only learned keys differ · A1 G8 · class: pass · source: sync-1 decision (RC-6).
    static let s63 = CatalogueScenario(id: "S-63", title: "Learned keys and one-time flags differ: no question, no hint, no restart", source: .a1, kind: .pass) {
        let scenario = Catalogue.scenario("S-63", macs: CatalogueG3Generations.specs([.A, .B], generation: 27))
            .settle()
            // Only learned keys and one-time flags differ between the two Macs.
            .learn(.A, "KnownItemTags")
            .learn(.A, "TitleChangingItemOwners")
            .learn(.A, "KnownApplications27")
            .setFlag(.A, "MacOS27LayoutSeeded")
            .setFlag(.A, "hasMigratedSettings")
            .setFlag(.A, "HasImportedIceSettings")
            .learn(.B, "KnownItemTags")
            .learn(.B, "KnownApplications27")
            .setFlag(.B, "hasMigratedGroups")
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
        let relaunched = scenario
            .relaunchAll()
            .expectPrompts(count: 0)
            .expect("the known applications are united silently, every other learned key stays local") { world in
                func tokens(_ mac: SimMacName, _ key: String) -> Set<String> {
                    Set(world.defaults(of: mac)[key]?.tokens ?? [])
                }
                var failures: [String] = []
                let known = tokens(.A, "KnownApplications27").union(tokens(.B, "KnownApplications27"))
                for mac in [SimMacName.A, .B] where tokens(mac, "KnownApplications27") != known {
                    failures.append("\(mac) lacks part of the known applications")
                }
                for key in ["KnownItemTags", "TitleChangingItemOwners"] where !tokens(.A, key).isDisjoint(with: tokens(.B, key)) {
                    failures.append("\(key) crossed between the Macs")
                }
                for key in ["MacOS27LayoutSeeded", "hasMigratedSettings", "HasImportedIceSettings"] where world.defaults(of: .B)[key] != nil {
                    failures.append("B took the flag \(key)")
                }
                return failures.isEmpty ? nil : failures.joined(separator: ", ")
            }
            .expectQuiet()
        return Catalogue.run(relaunched)
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-55": CatalogueText(
            setup: "A and B on N.",
            steps: "An app adds a menu bar item on A. On macOS 26 it gets the default placement; on macOS 27, Concealer27 places the new app. Seeding counts the same.",
            wrong: "The placement counted as a layout edit, so B showed a hint or a question.",
            must: "No hint on B. A Restart hint already showing on A stays Restart. The placement never replaces B's arrangement."
        ),
        "S-56": CatalogueText(
            setup: "A and B on N, Restart showing on A.",
            steps: "Command-click an item without moving it. Variant: the default new-item placement has left an unsaved item.",
            wrong: "It counted as a layout edit, so the hint became Choose Settings…, and the next push listed holzBar's placements as the user's.",
            must: "No edit."
        ),
        "S-57": CatalogueText(
            setup: "A and B on macOS 27, Restart showing on A.",
            steps: "Apply the current layout profile again by its hotkey.",
            wrong: "It counted as an edit.",
            must: "The hint stays Restart."
        ),
        "S-58": CatalogueText(
            setup: "A and B on N.",
            steps: "The user Command-drags an item that has no saved section. Then a newer version arrives from a Mac that knows the item.",
            wrong: "The move did not count, so the remote section was applied and the move was reverted silently.",
            must: "The move counts. A writes it, or asks if the other Mac moved the same item too."
        ),
        "S-59": CatalogueText(
            setup: "A and B on N.",
            steps: "A display is connected or the Mac wakes, so macOS moves items. Before the restore puts them back, the user Command-clicks or drags any item.",
            wrong: "The save stored the displaced section of every cached item and counted it as the user's arrangement. A wrote it over the other Macs' arrangements.",
            must: "Displaced items keep their saved sections. Only the item the user moved counts."
        ),
        "S-60": CatalogueText(
            setup: "A on N.",
            steps: "The user saves a section by dragging. A reconciliation that read the bar earlier then stores the item's old section.",
            wrong: "holzBar's stale placement replaced the user's fresh save, and the stale value synced.",
            must: "An automatic store never replaces a section the user saved after the read."
        ),
        "S-61": CatalogueText(
            setup: "A and B on N.",
            steps: "Drag an item in the Layout pane right after a wake.",
            wrong: "The restore reverted the move.",
            must: "The move is saved and synced, and the next restore never reverts it."
        ),
        "S-62": CatalogueText(
            setup: "A synced under beta1, then updated to beta2. Beta2 runs no migration, counts no edits and writes no version marker.",
            steps: "The user rearranges A's menu bar. A updates to N, and sync resumes.",
            wrong: "The layout counts as unchanged, and the join takes the folder's layout silently.",
            must: "On the first sync after an update from any earlier build, an existing layout counts as the user's, and holzBar asks if it differs."
        ),
        "S-63": CatalogueText(
            setup: "A and B on N. Only learned keys and one-time flags differ.",
            steps: "KnownItemTags, KnownApplications27, TitleChangingItemOwners, MacOS27LayoutSeeded, hasMigrated* or hasImportedPreviousSettings differ.",
            wrong: "A whole-file apply replaced the receiving Mac's KnownItemTags, and the automatic rewrites caused prompts on the other Mac.",
            must: "A silent union or OR merge, with no question, no hint and no restart."
        ),
    ]
}

/// The G8 scenarios, one test each.
@Suite("CatalogueG8Automatic")
struct CatalogueG8AutomaticTests {
    @Test("A1 G8: automatic versus user changes", arguments: CatalogueG8Automatic.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
