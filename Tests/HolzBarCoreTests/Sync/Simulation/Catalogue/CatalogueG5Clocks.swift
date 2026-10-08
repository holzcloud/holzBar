//
//  CatalogueG5Clocks.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G5 of the A1 regression catalogue (S-28 to S-33): clocks and dates. The redesigned engine orders versions by counters
/// and contexts, never by a date, so a clock that is behind, ahead or set back changes no decision. Each scenario is a
/// plain list of events (time passes with `advance`, so a run can be repeated), asserts its A1 Must, and then runs again
/// with clock offsets and clock steps drawn from the generator and asserts equal decisions (INV-F9).
nonisolated enum CatalogueG5Clocks {
    static let scenarios: [CatalogueScenario] = [s28] + s29 + [s30] + s31 + [s32, s33]

    static let tenMinutes: Int64 = 600_000

    // MARK: Building blocks

    /// Runs a scenario, then runs its events again under the clock offsets and steps of two generator seeds.
    static func run(_ scenario: SimScenario, macs: [SimMacSpec]) -> SimScenarioResult {
        var result = Catalogue.run(scenario)
        let setup = SimMetaSetup(seed: scenario.seed, macs: macs, brainFactory: Catalogue.brain)
        for clockSeed in [UInt64(1), 2] {
            let found = SimMetamorphic.clockIndependence(setup, scenario.events, clockSeed: clockSeed)
            result.failures += found.map { "scenario \"\(scenario.name)\": \($0.id) violated: \($0.description)" }
        }
        return result
    }

    static func specs(_ names: [SimMacName], generation: Int = 26, offsets: [SimMacName: Int64] = [:]) -> [SimMacSpec] {
        names.map { SimMacSpec($0, .redesign, generation: generation, running: true, clockOffsetMilliseconds: offsets[$0] ?? 0) }
    }

    /// The path of a Mac's own file, which depends on the seed and the Mac and on nothing else.
    static func ownPath(of mac: SimMacName, macs: [SimMacSpec], seed: UInt64) -> String {
        let probe = SimWorld(seed: seed, macs: macs, brainFactory: Catalogue.brain)
        return Catalogue.ownPath(probe, mac) ?? "holzBar/Macs/none.plist"
    }

    /// One arrangement step of a form (as in G3): a move on macOS 27, a drag of the local `ItemSections` on macOS 26.
    static func arrange(_ scenario: SimScenario, _ mac: SimMacName, generation: Int, section: Int, k: Int) -> SimScenario {
        CatalogueG3Generations.arrange(scenario, mac, generation: generation, section: section, k: k)
    }

    // MARK: S-28

    // S-28 · A change dated before the last sync · A1 G5 · class: pass · source: V1-#1, step J (RC-2, RC-1).
    static let s28 = CatalogueScenario(id: "S-28", title: "A change dated before the last sync is concurrent, whatever the dates say", source: .a1, kind: .pass) {
        let macs = specs([.A, .B], offsets: [.B: -tenMinutes])
        // A changes a setting and B applies it; B changes the setting, dated before A's last sync; A changes something else.
        let applies = Catalogue.scenario("S-28 applies", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.B)
            .advance(seconds: 60)
            .edit(.B, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 60)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .advance(seconds: 120)
            .expectHint(.A, present: true)
            .expectUser(.A, Catalogue.hover, 1)
            .expectPrompts(count: 0)
            .restartApp(.A)
            .restartApp(.B)
            .advance(seconds: 120)
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.rehide, 3)
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.rehide, 3)
            .expectPrompts(count: 0)
        // A changed the same setting meanwhile: A asks, and neither value is replaced.
        let asks = Catalogue.scenario("S-28 asks", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.B)
            .advance(seconds: 60)
            .provider(.offline(mac: .A, forMilliseconds: 3_600_000))
            .edit(.B, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.A, Catalogue.hover, value: Catalogue.user(4, Catalogue.hover))
            .advance(seconds: 60)
            .provider(.offline(mac: .A, forMilliseconds: 0))
            .advance(seconds: 3_700)
            .expectUser(.A, Catalogue.hover, 4)
            .expectUser(.B, Catalogue.hover, 2)
            .expect("A asks about both values") { world in
                let expected = SimPromptUnit(unit: Catalogue.hover, local: "u4@\(Catalogue.hover)", folder: "u2@\(Catalogue.hover)")
                return world.brains[.A]?.openPrompt?.shown.contains(expected) == true ? nil : "A's sheet shows \(world.brains[.A]?.openPrompt?.shown ?? [])"
            }
        return Catalogue.combine("S-28", [run(applies, macs: macs), run(asks, macs: macs)])
    }

    // MARK: S-29

    // S-29 · An older version's layout recorded as synced, then overwritten by a drag · A1 G5 · class: scope · source: V0-#5 (RC-2, RC-5).
    static let s29: [CatalogueScenario] = [
        CatalogueScenario(id: "S-29/26", title: "A lagging clock compares no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS29(generation: 26)
        },
        CatalogueScenario(id: "S-29/27", title: "A lagging clock never lets a drag overwrite a layout silently (generation 27)", source: .a1, kind: .scope) {
            runS29(generation: 27)
        },
    ]

    private static func runS29(generation: Int) -> SimScenarioResult {
        // B's clock lags by ten minutes in one world and runs two hours ahead in the other.
        let results = [-tenMinutes, 2 * 3_600_000].map { offset -> SimScenarioResult in
            let macs = specs([.A, .B], generation: generation, offsets: [.B: offset])
            let held = CatalogueBox<SimValue?>(nil)
            var scenario = Catalogue.scenario("S-29 offset \(offset / 1000) s", macs: macs)
            scenario = arrange(scenario, .A, generation: generation, section: 1, k: 1)
                .advance(seconds: 60)
                .restartApp(.B)
                .advance(seconds: 60)
            // 1. B arranges (L2) and writes. 2. A changes only a user setting and writes. 3. A drags.
            scenario = arrange(scenario, .B, generation: generation, section: 2, k: 2)
                .advance(seconds: 60)
                .noteArrangement(.B, generation: generation, in: held)
                .edit(.A, Catalogue.hover, value: Catalogue.user(5, Catalogue.hover))
                .advance(seconds: 60)
            scenario = arrange(scenario, .A, generation: generation, section: 3, k: 3)
                .advance(seconds: 120)
                .expectArrangement(.B, generation: generation, is: held)
                .expectHint(.B, present: true)
            if generation == 27 {
                scenario = scenario.expect("A asks before it replaces B's layout") { world in
                    Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
                }
            } else {
                scenario = scenario.expectNoLayoutQuestion().expectPrompts(count: 0)
            }
            return run(scenario, macs: macs)
        }
        return Catalogue.combine("S-29/\(generation)", results)
    }

    // MARK: S-30

    // S-30 · A version dated far in the future · A1 G5 · class: pass · source: R2 follow-up 5b301828 (RC-2).
    static let s30 = CatalogueScenario(id: "S-30", title: "One Mac's wrong clock never changes how the others order later versions", source: .a1, kind: .pass) {
        let days: Int64 = 3 * 24 * 3_600_000
        let macs = specs([.A, .B, .C], offsets: [.B: days])
        // B, three days ahead, writes; A applies it; C, on time, changes the setting afterwards.
        let scenario = Catalogue.scenario("S-30", macs: macs)
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.A)
            .restartApp(.C)
            .advance(seconds: 60)
            .expectUser(.A, Catalogue.hover, 1)
            .edit(.C, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 120)
            // The later version is the later version for everyone, however far ahead B's dates were.
            .expectHint(.A, present: true)
            .expectHint(.B, present: true)
            .restartApp(.A)
            .restartApp(.B)
            .advance(seconds: 120)
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.C, Catalogue.hover, 2)
            .expectPrompts(count: 0)
        return run(scenario, macs: macs)
    }

    // MARK: S-31

    // S-31 · A re-joining Mac adopts an older version · A1 G5 · class: scope · source: V3-#4, step AA (RC-2, RC-5).
    static let s31: [CatalogueScenario] = [
        CatalogueScenario(id: "S-31/26", title: "A re-joining Mac asks about settings only (generation 26)", source: .a1, kind: .scope) {
            runS31(generation: 26)
        },
        CatalogueScenario(id: "S-31/27", title: "A re-joining Mac never overwrites a layout it never took in (generation 27)", source: .a1, kind: .scope) {
            runS31(generation: 27)
        },
    ]

    private static func runS31(generation: Int) -> SimScenarioResult {
        let macs = specs([.A, .B], generation: generation, offsets: [.B: -5 * 60_000])
        let held = CatalogueBox<SimValue?>(nil)
        // B arranges and writes, dated before A's last sync. A turns sync off and on: the state is kept.
        var arrangement = Catalogue.scenario("S-31 arrangement", macs: macs)
        arrangement = arrange(arrangement, .B, generation: generation, section: 1, k: 1)
            .advance(seconds: 60)
            .noteArrangement(.B, generation: generation, in: held)
            .turnOff(.A)
            .advance(seconds: 30)
            .turnOn(.A)
            .advance(seconds: 120)
            .expectPrompts(count: 0)
        // Later A drags.
        arrangement = arrange(arrangement, .A, generation: generation, section: 2, k: 2)
            .advance(seconds: 120)
            .expectArrangement(.B, generation: generation, is: held)
        if generation == 27 {
            arrangement = arrangement.expect("A asks before it replaces an arrangement it never took in") { world in
                Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
            }
        } else {
            arrangement = arrangement.expectNoLayoutQuestion().expectPrompts(count: 0)
        }
        // Only units changed on both sides are asked.
        let settings = Catalogue.scenario("S-31 settings", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.B)
            .advance(seconds: 60)
            .turnOff(.A)
            .advance(seconds: 30)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .edit(.B, Catalogue.rehide, value: Catalogue.user(4, Catalogue.rehide))
            .advance(seconds: 60)
            .turnOn(.A)
            .advance(seconds: 120)
            .expect("A asks about the setting changed on both sides, and about nothing else") { world in
                let asked = Catalogue.shownUnits(world, .A)
                return Set(asked) == [Catalogue.hover] ? nil : "A's sheet shows \(asked)"
            }
            .expectUser(.A, Catalogue.hover, 2)
        return Catalogue.combine("S-31/\(generation)", [run(arrangement, macs: macs), run(settings, macs: macs)])
    }

    // MARK: S-32

    // S-32 · A clock set back, or two writes in the same second · A1 G5 · class: pass · source: V5, step AP (RC-2) [§5.2 pair 9].
    static let s32 = CatalogueScenario(id: "S-32", title: "A clock set back never reverts the last write", source: .a1, kind: .pass) {
        let macs = specs([.A, .B])
        let own = ownPath(of: .A, macs: macs, seed: 1)
        // A writes W1; the clock goes back a minute; A writes W2, dated before W1; the file is deleted; B changes a setting.
        let setBack = Catalogue.scenario("S-32 set back", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .clockStep(.A, milliseconds: -60_000)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 30)
            .provider(.delete(path: own))
            .advance(seconds: 30)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .advance(seconds: 120)
            .restartApp(.A)
            .advance(seconds: 120)
            .restartApp(.B)
            .advance(seconds: 120)
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.rehide, 3)
            .expectUser(.B, Catalogue.rehide, 3)
        // Two writes within one second: counters never repeat and the last write wins everywhere.
        let sameSecond = Catalogue.scenario("S-32 same second", macs: macs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(4, Catalogue.hover))
            .advance(milliseconds: 100)
            .edit(.A, Catalogue.hover, value: Catalogue.user(5, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.B)
            .advance(seconds: 60)
            .expectUser(.A, Catalogue.hover, 5)
            .expectUser(.B, Catalogue.hover, 5)
            .expectPrompts(count: 0)
        return Catalogue.combine("S-32", [run(setBack, macs: macs), run(sameSecond, macs: macs)])
    }

    // MARK: S-33

    // S-33 · Keep over a version dated at or before the answered one · A1 G5 · class: pass · source: V2-#1, step S (RC-8, RC-2).
    static let s33 = CatalogueScenario(id: "S-33", title: "Keep replaces exactly the version that was answered", source: .a1, kind: .pass) {
        let macs = specs([.A, .B])
        // Both Macs change the setting and A's sheet opens. B's clock goes back; B changes the setting again and another
        // setting, and both reach A. A chooses Keep.
        let scenario = Catalogue.scenario("S-33", macs: macs)
            .provider(.offline(mac: .A, forMilliseconds: 3_600_000))
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 30)
            .provider(.offline(mac: .A, forMilliseconds: 0))
            .advance(seconds: 3_700)
            .expect("A's sheet is open") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
            .clockStep(.B, milliseconds: -5 * 60_000)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .edit(.B, Catalogue.hover, value: Catalogue.user(4, Catalogue.hover))
            .advance(seconds: 120)
            .answer(.A, .keep)
            .advance(seconds: 120)
            // Keep took only the value the sheet showed: B's newer version survives and is asked about again.
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 4)
            .expect("B's newer value is still a live sibling on A") { world in
                Catalogue.live(world, .A, Catalogue.hover).contains(Catalogue.user(4, Catalogue.hover)) ? nil : "A's replica holds \(Catalogue.live(world, .A, Catalogue.hover).map(\.canonical))"
            }
            .restartApp(.A)
            .advance(seconds: 120)
            .expect("A asks again about the version that arrived later") { world in
                let shown = world.brains[.A]?.openPrompt?.shown ?? []
                let expected = SimPromptUnit(unit: Catalogue.hover, local: "u1@\(Catalogue.hover)", folder: "u4@\(Catalogue.hover)")
                return shown.contains(expected) ? nil : "A's sheet shows \(shown)"
            }
            .expectUser(.A, Catalogue.rehide, 3)
        return run(scenario, macs: macs)
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-28": CatalogueText(
            setup: "A and B on the redesigned build, same macOS. B's clock is about ten minutes behind.",
            steps: "A changes a setting and B applies it. B changes Show on hover, dated before A's last sync. A changes something.",
            wrong: "A takes B's version for not newer, ignores it, and its next write overwrites B's change silently.",
            must: "A treats B's change as concurrent, whatever the dates say. It asks if A also changed something in that setting, and otherwise applies it."
        ),
        "S-29": CatalogueText(
            setup: "A and B on the redesigned build. B's version is dated at or before A's last sync (a lagging clock), or more than one hour ahead.",
            steps: "B drags (L2) and writes. A changes only a user setting and writes; the file keeps L2. A drags.",
            wrong: "A writes L1 plus the drag over L2 without asking.",
            must: "A takes L2 in, or asks before replacing it. Synced means held on this Mac."
        ),
        "S-30": CatalogueText(
            setup: "B's clock is days ahead, or a date is corrupt.",
            steps: "B writes, and A records or answers about that version.",
            wrong: "The future date became A's last sync, so every later version of the other Macs counted as not newer.",
            must: "One Mac's wrong clock never changes how the other Macs order later versions."
        ),
        "S-31": CatalogueText(
            setup: "A and B on the redesigned build, same macOS. B's clock is a few minutes behind.",
            steps: "B drags and writes, dated before A's last sync. On A, turn sync off and on. Later A drags.",
            wrong: "The joining A adopts B's version and records its layout as synced without taking it in; A's next drag writes over it without asking.",
            must: "A asks before joining over an arrangement it never took in, or takes it in. It never overwrites it silently later."
        ),
        "S-32": CatalogueText(
            setup: "A and B on the redesigned build.",
            steps: "A changes a setting (W1). Set A's clock back a minute and change it back (W2, dated before W1); a variant has two writes in one second. Delete the file. B changes a setting. A checks.",
            wrong: "A write was identified by its wall-clock date in whole seconds; B's version seemed to hold A's last write and A applied it silently, reverting W2.",
            must: "A's last write is never reverted whatever its clock did: A asks, or the versions merge by their counters."
        ),
        "S-33": CatalogueText(
            setup: "A and B on the redesigned build.",
            steps: "Both change Show on hover and A's sheet is open. Set B's clock back, change another setting on B and let it reach A. On A choose Keep This Mac's Settings.",
            wrong: "Keep accepted any version dated at or before the answered one, so A wrote over B's new version, which nobody had asked about.",
            must: "Keep replaces only the exact version that was answered. Anything else asks again."
        ),
    ]
}

/// The G5 scenarios, one test each.
@Suite("CatalogueG5Clocks")
struct CatalogueG5ClocksTests {
    @Test("A1 G5: clocks and dates", arguments: CatalogueG5Clocks.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
