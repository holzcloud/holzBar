//
//  CatalogueG1Joining.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G1 of the A1 regression catalogue (S-01 to S-08): joining, identity and routine writes. Each scenario runs the
/// real engine in the simulator under the safety and layout oracles.
nonisolated enum CatalogueG1Joining {
    static let scenarios: [CatalogueScenario] = [s01, s02, s03, s04, s05, s06, s07] + s08

    // MARK: Worlds

    /// Mac A runs with sync on in an empty folder; B has sync off and `defaults`, and the folder `F1` is on its disk.
    static func joinerSpecs(_ defaults: [String: SimValue] = [:], aGeneration: Int = 26, bGeneration: Int = 27) -> [SimMacSpec] {
        [
            SimMacSpec(.A, .redesign, generation: aGeneration, running: true),
            SimMacSpec(.B, .redesign, generation: bGeneration, enabled: false, folder: nil, running: true, defaults: defaults, syncedFolder: "F1"),
        ]
    }

    /// Two Macs that both run with sync on in `F1`.
    static func pairSpecs(aGeneration: Int = 26, bGeneration: Int = 27) -> [SimMacSpec] {
        [
            SimMacSpec(.A, .redesign, generation: aGeneration, running: true),
            SimMacSpec(.B, .redesign, generation: bGeneration, running: true),
        ]
    }

    /// A has been in its group for weeks: it holds three settings that B does not know.
    static func weeksOld(_ scenario: SimScenario) -> SimScenario {
        scenario
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .edit(.A, Catalogue.menus, value: Catalogue.user(3, Catalogue.menus))
            .settle()
    }

    // MARK: S-01

    // S-01 · A second Mac joins with its defaults · A1 G1 · class: pass · source: F-02a (RC-1, RC-7).
    static let s01 = CatalogueScenario(id: "S-01", title: "A second Mac joins a folder of weeks-old settings", source: .a1, kind: .pass) {
        // Absent keys only: B adopts silently, and A never changes.
        let absent = weeksOld(Catalogue.scenario("S-01 absent keys", macs: joinerSpecs()))
            .checkpoint()
            .turnOn(.B)
            .settle()
            .expectPrompts(count: 0)
            .expectNoWrite(.A)
            .expectHint(.A, present: false)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.menus, 3)
            .expectUser(.A, Catalogue.hover, 1)
            .expectHint(.B, present: false)
            .expectHint(.A, present: false)
            .expectQuiet()

        // Present, differing keys: B asks, nothing changes before the answer, and A changes only after Keep.
        let differing: [String: SimValue] = [Catalogue.hover: Catalogue.pre(.B)]
        let pre = SimPromptUnit(unit: Catalogue.hover, local: "pre(B)", folder: "u1@\(Catalogue.hover)")
        func asked(_ name: String) -> SimScenario {
            weeksOld(Catalogue.scenario(name, macs: joinerSpecs(differing)))
                .checkpoint()
                .turnOn(.B)
                .settle()
                .expectPrompts(count: 1, mac: .B)
                .expect("the question names both values") { world in
                    world.brains[.B]?.openPrompt?.shown == [pre] ? nil : "the sheet shows \(world.brains[.B]?.openPrompt?.shown.map(\.unit) ?? [])"
                }
                .expectValue(.B, Catalogue.hover, Catalogue.pre(.B))
                .expectUser(.A, Catalogue.hover, 1)
                .expectNoWrite(.A)
                .expectHint(.A, present: false)
        }
        let keep = asked("S-01 Keep")
            .answer(.B, .keep)
            .settle()
            .expectHint(.A, present: true)
            .expectUser(.A, Catalogue.hover, 1)
            .restartApp(.A)
            .settle()
            .expectValue(.A, Catalogue.hover, Catalogue.pre(.B))
            .expectValue(.B, Catalogue.hover, Catalogue.pre(.B))
            .expectUser(.A, Catalogue.rehide, 2)
            // The keys B did not hold arrive on B with its restart.
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectQuiet()
        let use = asked("S-01 Use")
            .answer(.B, .use)
            .settle()
            .expectHint(.A, present: false)
            .expectUser(.A, Catalogue.hover, 1)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectQuiet()
        let cancel = asked("S-01 Cancel")
            .answer(.B, .cancel)
            .settle()
            .expectNoWrite(.A)
            .expectHint(.A, present: false)
            .expectValue(.B, Catalogue.hover, Catalogue.pre(.B))
            .expect("sync stays off on B") { world in world.state(of: .B).enabled ? "B turned sync on" : nil }
            .expectQuiet()
        return Catalogue.combine("S-01", [absent, keep, use, cancel].map(Catalogue.run))
    }

    // MARK: S-02

    // S-02 · A relaunch with nothing changed · A1 G1 · class: pass · source: F-02b (RC-1).
    static let s02 = CatalogueScenario(id: "S-02", title: "Relaunches with nothing changed write nothing and show no hint", source: .a1, kind: .pass) {
        var scenario = weeksOld(Catalogue.scenario("S-02", macs: pairSpecs()))
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .checkpoint()
        // A hundred relaunches, alternating between the two Macs.
        for round in 0..<100 {
            scenario = scenario.restartApp(round.isMultiple(of: 2) ? .A : .B).settle()
        }
        return Catalogue.run(
            scenario
                .expectNoWrite(.A)
                .expectNoWrite(.B)
                .expectPrompts(count: 0)
                .expectHint(.A, present: false)
                .expectHint(.B, present: false)
                .expectQuiet()
        )
    }

    // MARK: S-03

    // S-03 · A Mac behind writes over a newer version · A1 G1 · class: pass · source: F-02b (RC-1, RC-3).
    static let s03 = CatalogueScenario(id: "S-03", title: "A Mac behind never replaces a version it has not read", source: .a1, kind: .pass) {
        // B is behind: A's change has not reached it when B launches and changes another setting.
        let behind = Catalogue.scenario("S-03 behind", macs: pairSpecs())
            .offline(.B, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .restartApp(.B)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 30)
            .expect("B publishes only its own entry") { world in
                Catalogue.publishedEntries(world, .B, Catalogue.hover).isEmpty ? nil : "B's file carries an entry for \(Catalogue.hover)"
            }
            .online(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectPrompts(count: 0)
            .expectHint(.B, present: true)
            .restartApp(.B)
            .restartApp(.A)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectQuiet()

        // The current version is dataless on B: B waits and writes nothing over it.
        let dataless = Catalogue.scenario("S-03 dataless", macs: pairSpecs())
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .perform("evict A's file on B") { world in
                if let path = Catalogue.ownPath(world, .A) { world.step(.provider(.evict(path: path, mac: .B))) }
                return []
            }
            .restartApp(.B)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 30)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)

        // Both Macs changed the same setting: holzBar asks, and neither value is replaced before the answer.
        let both = Catalogue.scenario("S-03 same setting", macs: pairSpecs())
            .offline(.B, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 2)
            .expect("both Macs are asked") { world in
                let asked = [SimMacName.A, .B].filter { world.brains[$0]?.openPrompt != nil }
                return asked.count == 2 ? nil : "only \(asked) are asked about \(Catalogue.hover)"
            }
        return Catalogue.combine("S-03", [behind, dataless, both].map(Catalogue.run))
    }

    // MARK: S-04

    // S-04 · Later, followed by any push · A1 G1 · class: pass · source: F-02c (RC-1, RC-6, RC-9).
    static let s04 = CatalogueScenario(id: "S-04", title: "A waiting version survives Later and every push", source: .a1, kind: .pass) {
        // Both Macs changed the setting while A was offline; A is asked and chooses Later.
        func later(_ name: String) -> SimScenario {
            Catalogue.scenario(name, macs: pairSpecs())
                .offline(.A, seconds: 3_600)
                .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 30)
                .online(.A)
                .settle()
                .expect("A is asked") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
                .answer(.A, .later)
                .expectUser(.A, Catalogue.hover, 2)
        }
        // Pushes after Later: a user change of another setting and holzBar's own writes.
        let pushes = later("S-04 pushes")
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .learn(.A, "KnownItemTags")
            .setFlag(.A, "HasImportedIceSettings")
            .settle()
            .expect("B's version still waits, unsuperseded") { world in
                let live = Catalogue.live(world, .A, Catalogue.hover)
                return live.contains(Catalogue.user(1, Catalogue.hover)) ? nil : "A's replica holds \(live.map(\.canonical))"
            }
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 1)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.hover, 2)
        // A user change of the same setting after Later is a change on both Macs: a question, never a replacement.
        // The ground truth agrees with the engine (plan 28-13): Later decides nothing, so the user was not informed of
        // the waiting version and the change after Later is concurrent with it (A1 S-04, A2 R-FUN-4 and SC-14).
        let sameSetting = later("S-04 same setting")
            .edit(.A, Catalogue.hover, value: Catalogue.user(4, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 4)
            .expect("A asks about its newer value and B's") { world in
                let shown = world.brains[.A]?.openPrompt?.shown ?? []
                let expected = SimPromptUnit(unit: Catalogue.hover, local: "u4@\(Catalogue.hover)", folder: "u1@\(Catalogue.hover)")
                return shown.contains(expected) ? nil : "A's sheet shows \(shown)"
            }
            .expect("B's version is still a live sibling on A") { world in
                Catalogue.live(world, .A, Catalogue.hover).contains(Catalogue.user(1, Catalogue.hover)) ? nil : "B's value is gone from A's replica"
            }

        return Catalogue.combine("S-04", [pushes, sameSetting].map(Catalogue.run))
    }

    // S-05 · The notice is open while pushes run · A1 G1 · class: pass · source: modal-alerts decision (4) (RC-9, RC-1).
    static let s05 = CatalogueScenario(id: "S-05", title: "Nothing A pushes while a remote version waits supersedes it", source: .a1, kind: .pass) {
        // The Restart notice is showing: A pushes a user change and holzBar's own writes.
        let notice = Catalogue.scenario("S-05 notice", macs: pairSpecs())
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .expectHint(.A, present: true)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .learn(.A, "KnownItemTags")
            .setFlag(.A, "HasImportedIceSettings")
            .settle()
            .expectHint(.A, present: true)
            .expect("A's replica still holds B's entry alone") { world in
                let live = Catalogue.live(world, .A, Catalogue.hover)
                return live == [Catalogue.user(1, Catalogue.hover)] ? nil : "A's replica holds \(live.map(\.canonical)) for \(Catalogue.hover)"
            }
            .expect("A published no entry for the waiting unit") { world in
                let own = Catalogue.state(world, .A)?.mac
                let mine = Catalogue.publishedEntries(world, .A, Catalogue.hover).filter { $0.dot.mac == own }
                return mine.isEmpty ? nil : "A's file carries an entry of its own for \(Catalogue.hover)"
            }
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.hover, 1)
            .expectQuiet()

        // The sheet is open: both Macs changed the setting. A keeps pushing, and the answer applies B's version.
        let sheet = Catalogue.scenario("S-05 sheet", macs: pairSpecs())
            .offline(.A, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .online(.A)
            .settle()
            .expect("A is asked") { world in world.brains[.A]?.openPrompt == nil ? "A shows no sheet" : nil }
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .learn(.A, "KnownItemTags")
            .settle()
            .expect("the sheet stays open, with B's version still waiting") { world in
                guard world.brains[.A]?.openPrompt != nil else { return "A's sheet closed" }
                let live = Catalogue.live(world, .A, Catalogue.hover)
                return live.contains(Catalogue.user(1, Catalogue.hover)) ? nil : "A's replica holds \(live.map(\.canonical))"
            }
            .answer(.A, .use)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 3)
        return Catalogue.combine("S-05", [notice, sheet].map(Catalogue.run))
    }

    // S-06 · A Mac set up by Migration Assistant, a restore or a clone · A1 G1 · class: pass · source: F-38 (RC-10).
    static let s06 = CatalogueScenario(id: "S-06", title: "A clone gets its own identity and joins with its replica", source: .a1, kind: .pass) {
        final class Identities { var before: String? }
        let seen = Identities()
        let clone = Catalogue.scenario("S-06", macs: pairSpecs())
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .settle()
            .perform("note B's identity") { world in
                seen.before = SimMacRedesignProbe.id(of: world, .B)
                return []
            }
            .clone(from: .A, to: .B)
            .launch(.B)
            .settle()
            .restartApp(.A)
            .settle()
            .expect("B has an identity of its own") { world in
                let a = SimMacRedesignProbe.id(of: world, .A)
                let b = SimMacRedesignProbe.id(of: world, .B)
                if a == nil || b == nil || a == b { return "A is \(a ?? "-"), B is \(b ?? "-")" }
                return b == seen.before ? "B kept the identity it had before the clone" : nil
            }
            .expect("B keeps the replica of the clone") { world in
                guard let a = SimMacRedesignProbe.id(of: world, .A), let state = Catalogue.state(world, .B) else { return "B has no state" }
                return state.previousMacIDs.contains { $0.rawValue == a } ? nil : "B's state does not remember the identity it was cloned from"
            }
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 0)
            .expectSilent()
            // Both Macs then see each other's changes.
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .edit(.B, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
            .settle()
            .expectHint(.A, present: true)
            .expectHint(.B, present: true)
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectUser(.A, Catalogue.spacing, 3)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(clone)
    }

    // S-07 · Joining without a conflict · A1 G1 · class: pass · source: sync-1 test list.
    static let s07 = CatalogueScenario(id: "S-07", title: "Four joins that must not ask", source: .a1, kind: .pass) {
        let equal = Catalogue.pre(.A)
        let specs = [
            SimMacSpec(.A, .redesign, generation: 26, enabled: false, folder: nil, running: true, defaults: [Catalogue.hover: equal], syncedFolder: "F1"),
            SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, defaults: [Catalogue.hover: equal], syncedFolder: "F1"),
        ]
        let joins = Catalogue.scenario("S-07", macs: specs)
            // 1. No file: A writes and asks nothing.
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            .expect("A published its settings") { world in
                Catalogue.publishedEntries(world, .A, Catalogue.hover).isEmpty ? "A wrote no entry for \(Catalogue.hover)" : nil
            }
            // 2. This Mac's own file: adopt.
            .turnOff(.A)
            .settle()
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            // 3. A file whose settings equal this Mac's: adopt.
            .turnOn(.B)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            // 4. A re-identified Mac (S-06) with equal settings.
            .clone(from: .A, to: .B)
            .launch(.B)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            .expectValue(.A, Catalogue.hover, equal)
            .expectValue(.B, Catalogue.hover, equal)
            .expectQuiet()
        return Catalogue.run(joins)
    }

    // S-08 · Sync was on but never reached the folder · A1 G1 · class: scope · source: V0-#7 (RC-6, RC-7).
    static let s08: [CatalogueScenario] = [
        CatalogueScenario(id: "S-08/26", title: "Sync was on but never reached the folder (generation 26)", source: .a1, kind: .scope) {
            runS08(generation: 26)
        },
        CatalogueScenario(id: "S-08/27", title: "Sync was on but never reached the folder (generation 27)", source: .a1, kind: .scope) {
            runS08(generation: 27)
        },
    ]

    /// The generation-26 form asserts the arrangement is never part of a question and stays untouched; the
    /// generation-27 form asserts the Mac's own `l27` entry that differs from the group's is asked about and never
    /// silently replaced (D-04, D-11).
    private static func runS08(generation: Int) -> SimScenarioResult {
        let own = Catalogue.pre(.A)
        let handMade = generation == 27
            ? Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 2, token: own)])
            : Catalogue.sectionsDefaults(own)
        let specs = [
            SimMacSpec(.A, .redesign, generation: generation, running: false, defaults: handMade),
            SimMacSpec(.B, .redesign, generation: generation, running: true, defaults: generation == 27 ? [:] : Catalogue.sectionsDefaults(Catalogue.pre(.B))),
        ]
        var scenario = Catalogue.scenario("S-08", macs: specs)
            .provider(.unmount(mac: .A))
            .launch(.A)
            .settle()
        // B is in the group; its arrangement differs from A's hand-made one.
        if generation == 27 {
            scenario = scenario.moveApp27(.B, bundle: Catalogue.appA, section: 1)
        }
        scenario = scenario
            .settle()
            .provider(.mount(mac: .A))
            .restartApp(.A)
            .settle()
        if generation == 27 {
            return Catalogue.run(
                scenario
                    .expectPrompts(count: 1, mac: .A)
                    .expect("A asks about its own entry") { world in
                        Catalogue.shownUnits(world, .A).contains(Catalogue.layoutA) ? nil : "A's sheet shows \(Catalogue.shownUnits(world, .A))"
                    }
                    .expectKey(.A, "MacOS27Layout", .dictionary([Catalogue.appA: Catalogue.arrangement(section: 2, token: own)]))
                    .expectHint(.B, present: false)
                    .answer(.A, .keep)
                    .settle()
                    .expectKey(.A, "MacOS27Layout", .dictionary([Catalogue.appA: Catalogue.arrangement(section: 2, token: own)]))
                    .expectHint(.B, present: true)
            )
        }
        return Catalogue.run(
            scenario
                .expectPrompts(count: 0)
                .expectNoLayoutQuestion()
                .expectKey(.A, Catalogue.sections, Catalogue.sectionsDefaults(own)[Catalogue.sections])
                .expectKey(.B, Catalogue.sections, Catalogue.sectionsDefaults(Catalogue.pre(.B))[Catalogue.sections])
                .expectSilent()
        )
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-01": CatalogueText(
            setup: "A (any macOS) has synced for weeks. B is a fresh install.",
            steps: "On B, Settings, Advanced, Sync, Turn On…, and choose A's folder.",
            wrong: "B writes its defaults over the file without reading it; A's configuration is gone on both Macs.",
            must: "B reads before it writes. Defaults or equal settings: B adopts silently. Differing settings: Use, Keep or Cancel. A changes only if B's user chose Keep."
        ),
        "S-02": CatalogueText(
            setup: "A and B have synced, any macOS.",
            steps: "Quit and reopen A.",
            wrong: "A rewrites the file with a fresh date at every launch; B offers a restart for identical settings and the two ping-pong.",
            must: "No write without a change of content, and no hint anywhere."
        ),
        "S-03": CatalogueText(
            setup: "A and B, any macOS.",
            steps: "A changes a setting and writes. Before B's sync app delivers that version, B launches or changes something.",
            wrong: "B writes its older state with a newer date and A applies it silently at launch.",
            must: "B never replaces a version it has not read; if it cannot read the current version it waits. A's change survives. A setting changed on both Macs is asked about."
        ),
        "S-04": CatalogueText(
            setup: "A and B, any macOS.",
            steps: "B changes a setting and A shows the hint. On A, choose Later. A pushes: after a user change, or after holzBar writes a learned key by itself.",
            wrong: "A's push overwrites B's version; A never applies B's change and B loses it at its next launch.",
            must: "B's version keeps waiting and automatic writes never push over it. A user change on A after Later turns into a question."
        ),
        "S-05": CatalogueText(
            setup: "A and B on the redesigned build.",
            steps: "B writes and A shows the notice or sheet. While it is open the app keeps running and any defaults change fires the debouncer.",
            wrong: "A pushes its own settings over B's newer file; the file is then from this Mac, Restart applies nothing and B's change is lost silently.",
            must: "Nothing A writes supersedes a waiting entry. Restart applies exactly the version that was offered."
        ),
        "S-06": CatalogueText(
            setup: "iMac A. MacBook B is set up from A by Migration Assistant. Both sync.",
            steps: "Launch B.",
            wrong: "Both Macs share one sync ID, each takes the other's files for its own, nothing is applied and the last writer wins.",
            must: "B gets its own identity (the hardware hash never leaves the Mac), keeps the replica, and then behaves as a joining Mac (S-01, S-07)."
        ),
        "S-07": CatalogueText(
            setup: "A Mac joins a folder.",
            steps: "Joining with no file; with this Mac's own file; with a file whose settings equal this Mac's; a re-identified Mac with equal settings.",
            wrong: "A question, or an unnecessary write that sends hints to the other Macs.",
            must: "No question, and no hint on any Mac."
        ),
        "S-08": CatalogueText(
            setup: "A had sync on but never reached the folder (iCloud Drive off). Its arrangement is hand-made. Later the folder becomes reachable, with settings equal to A's.",
            steps: "A updates to the redesigned build; the folder appears.",
            wrong: "The migration seeds no layout edits because sync is on; the join then takes the folder's arrangement silently over the user's.",
            must: "An arrangement on a Mac that never completed a sync counts as the user's, and holzBar asks if it differs."
        ),
    ]
}

/// The G1 scenarios, one test each.
@Suite("CatalogueG1Joining")
struct CatalogueG1JoiningTests {
    @Test("A1 G1: joining, identity and routine writes", arguments: CatalogueG1Joining.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
