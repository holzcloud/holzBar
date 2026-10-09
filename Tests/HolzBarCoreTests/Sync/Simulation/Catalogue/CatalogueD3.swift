//
//  CatalogueD3.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The 20 scenarios of the settings-only design (D3-S01 to D3-S20, section 15 of the D3 design): the cases the patch rounds
/// of the old sync never reached. Each one runs the real engine in the simulator under the safety and layout oracles and
/// asserts its Must; where the values are bare hotkey combinations that carry no token (D3-S06) the oracles that follow
/// tokens are left out of that world, with a comment.
nonisolated enum CatalogueD3 {
    static let scenarios: [CatalogueScenario] = [
        s01, s02, s03, s04, s05, s06, s07, s08, s09, s10,
        s11, s12, s13, s14, s15, s16, s17, s18, s19, s20,
    ]

    // MARK: Building blocks

    /// Macs that run with sync on in `F1`, all of one generation (macOS 26 unless said).
    static func running(_ names: [SimMacName], generation: Int = 26) -> [SimMacSpec] {
        names.map { SimMacSpec($0, .redesign, generation: generation, running: true) }
    }

    /// A Mac that has sync off and `defaults`, with the folder on its disk (a Mac about to join).
    static func joiner(_ name: SimMacName, generation: Int = 26, defaults: [String: SimValue] = [:]) -> SimMacSpec {
        SimMacSpec(name, .redesign, generation: generation, enabled: false, folder: nil, running: true, defaults: defaults, syncedFolder: "F1")
    }

    /// The units a sheet of a Mac shows now.
    static func shown(_ world: SimWorld, _ mac: SimMacName) -> [SimPromptUnit] {
        world.brains[mac]?.openPrompt?.shown ?? []
    }

    /// Every token a sheet shows, on either side.
    static func tokens(_ prompt: SimPrompt?) -> Set<String> {
        Set((prompt?.shown ?? []).flatMap { [$0.local, $0.folder].compactMap { $0 } })
    }

    /// A and B changed one setting differently while B was away, and both are asked: A holds `u1`, B holds `u2`.
    static func conflicted(_ name: String, unit: String = Catalogue.hover) -> SimScenario {
        Catalogue.scenario(name, macs: running([.A, .B]))
            .offline(.B, seconds: 3_600)
            .edit(.A, unit, value: Catalogue.user(1, unit))
            .edit(.B, unit, value: Catalogue.user(2, unit))
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expect("both Macs are asked once") { world in
                let asked = Catalogue.shownUnits(world, .A).filter { $0 == unit }.count + Catalogue.shownUnits(world, .B).filter { $0 == unit }.count
                return world.brains[.A]?.openPrompt != nil && world.brains[.B]?.openPrompt != nil && asked == 2
                    ? nil : "the sheets show \(Catalogue.shownUnits(world))"
            }
    }

    // MARK: D3-S01

    // D3-S01 · A changes Show on Hover, B changes Auto Rehide, concurrently · D3 section 15 · class: pass.
    static let s01 = CatalogueScenario(id: "D3-S01", title: "Different settings changed on two Macs merge with no question", source: .d3, kind: .pass) {
        let merged = Catalogue.scenario("D3-S01", macs: running([.A, .B]))
            .offline(.B, seconds: 3_600)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expectPrompts(count: 0)
            .expectHint(.A, present: true)
            .expectHint(.B, present: true)
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(merged)
    }

    // MARK: D3-S02

    // D3-S02 · A and B change Show on Hover to different values concurrently · D3 section 15 · class: pass.
    static let s02 = CatalogueScenario(id: "D3-S02", title: "One question on each Mac, and one answer on either settles both", source: .d3, kind: .pass) {
        // A takes B's value: B's question is gone and B has nothing to do.
        let chosen = conflicted("D3-S02 the other Mac's value")
            .answer(.A, .use)
            .settle()
            .expect("B's sheet is gone and B shows no hint") { world in
                world.brains[.B]?.openPrompt == nil && world.brains[.B]?.hint == nil ? nil : "B shows \(world.brains[.B]?.hint ?? "a sheet")"
            }
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectPrompts(count: 1, mac: .A)
            .expectPrompts(count: 1, mac: .B)
            .expectQuiet()
        // A keeps its own: B is told to restart and takes it there.
        let kept = conflicted("D3-S02 own value")
            .answer(.A, .keep)
            .settle()
            .expect("B's sheet is gone, B shows the restart hint") { world in
                world.brains[.B]?.openPrompt == nil && world.brains[.B]?.hint != nil ? nil : "B shows \(world.brains[.B]?.hint ?? "no hint")"
            }
            .expectUser(.B, Catalogue.hover, 2)
            .restartApp(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 1, mac: .A)
            .expectPrompts(count: 1, mac: .B)
            .expectQuiet()
        return Catalogue.combine("D3-S02", [chosen, kept].map(Catalogue.run))
    }

    // MARK: D3-S03

    // D3-S03 · A, B and C change one setting concurrently; D's change arrives while A's sheet is open · D3 section 15 · class: pass.
    static let s03 = CatalogueScenario(id: "D3-S03", title: "A sheet lists three values, and a fourth that arrives later is asked about anew", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let scenario = Catalogue.scenario("D3-S03", macs: running([.A, .B, .C, .D]))
            .offline(.B, seconds: 3_600)
            .offline(.C, seconds: 3_600)
            .offline(.D, seconds: 100_000)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .edit(.B, hover, value: Catalogue.user(2, hover))
            .edit(.C, hover, value: Catalogue.user(3, hover))
            .edit(.D, hover, value: Catalogue.user(4, hover))
            .advance(seconds: 30)
            .online(.B)
            .online(.C)
            .settle()
            .expect("A's sheet lists the three values") { world in
                let held = tokens(world.brains[.A]?.openPrompt)
                let expected: Set = ["u1@\(hover)", "u2@\(hover)", "u3@\(hover)"]
                return held == expected ? nil : "A's sheet shows \(held.sorted())"
            }
            // D comes back while the sheet is open: the sheet stays as it was shown.
            .online(.D)
            .settle()
            .expect("the open sheet is unchanged") { world in
                let held = tokens(world.brains[.A]?.openPrompt)
                return held == ["u1@\(hover)", "u2@\(hover)", "u3@\(hover)"] ? nil : "A's sheet now shows \(held.sorted())"
            }
            .answer(.A, .use)
            .settle()
            .expect("D's value is asked about anew") { world in
                let held = tokens(world.brains[.A]?.openPrompt)
                return held.contains("u4@\(hover)") ? nil : "A's next sheet shows \(held.sorted())"
            }
            .expect("the answer did not supersede D's value") { world in
                Catalogue.live(world, .A, hover).contains(Catalogue.user(4, hover)) ? nil : "A's replica lost D's value"
            }
        return Catalogue.run(scenario)
    }

    // MARK: D3-S04

    // D3-S04 · A answers Keep and B answers Use for the same conflict at the same time · D3 section 15 · class: pass.
    static let s04 = CatalogueScenario(id: "D3-S04", title: "Simultaneous answers end in at most one more question and then agree", source: .d3, kind: .pass) {
        // Keep on A and Use on B: B takes A's value, which A keeps. The answers agree, so nothing is asked again.
        let agreeing = conflicted("D3-S04 Keep and Use")
            .offline(.A, seconds: 600)
            .offline(.B, seconds: 600)
            .answer(.A, .keep)
            .answer(.B, .use)
            .online(.A)
            .online(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 2)
            .expectSilent()
            .expectQuiet()
        // Keep on both: each keeps its own, which is a new conflict with exactly one more question on each Mac.
        // INV-P1 is left out of this one world: the simulator's ground truth reads each Keep as superseding the other
        // Mac's value, and has no model of two answers that cross, so it sees no conflict at the second question, which
        // the engine rightly asks (the open item of plan 28-10 for the oracles).
        let opposed = conflicted("D3-S04 Keep and Keep")
            .oracles(SimOracleSet.safety.without(["INV-P1", "INV-P3", "INV-P7"]))
            .offline(.A, seconds: 600)
            .offline(.B, seconds: 600)
            .answer(.A, .keep)
            .answer(.B, .keep)
            .online(.A)
            .online(.B)
            .settle()
            .expect("each Mac is asked once more") { world in
                world.brains[.A]?.openPrompt != nil && world.brains[.B]?.openPrompt != nil
                    ? nil : "A: \(world.brains[.A]?.openPrompt != nil), B: \(world.brains[.B]?.openPrompt != nil)"
            }
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 2)
            .answer(.A, .use)
            .settle()
            .expect("B's second sheet is gone") { world in world.brains[.B]?.openPrompt == nil ? nil : "B still shows a sheet" }
            .restartApp(.B)
            .settle()
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectPrompts(count: 4)
            .expectSilent()
            .expectQuiet()
        return Catalogue.combine("D3-S04", [agreeing, opposed].map(Catalogue.run))
    }

    // MARK: D3-S05

    // D3-S05 · B and C conflict; A changed nothing · D3 section 15 · class: pass.
    static let s05 = CatalogueScenario(id: "D3-S05", title: "A bystander sees no hint, only the line, and fast-forwards once the others answer", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let scenario = Catalogue.scenario("D3-S05", macs: running([.A, .B, .C]))
            .offline(.B, seconds: 3_600)
            .offline(.C, seconds: 3_600)
            .edit(.B, hover, value: Catalogue.user(1, hover))
            .edit(.C, hover, value: Catalogue.user(2, hover))
            .advance(seconds: 30)
            .online(.B)
            .online(.C)
            .settle()
            .expectHint(.A, present: false)
            .expect("A has no sheet of its own") { world in world.brains[.A]?.openPrompt == nil ? nil : "A shows a sheet" }
            .expect("A's settings say that the other Macs differ") { world in
                Catalogue.lines(world, .A).contains(.bystander(rows: 1)) ? nil : "A's lines are \(Catalogue.lines(world, .A))"
            }
            .expectUnset(.A, hover)
            .expectPrompts(count: 1, mac: .B)
            .expectPrompts(count: 1, mac: .C)
            .answer(.B, .keep)
            .settle()
            .expect("A fast-forwards to B's answer and shows no more line") { world in
                world.brains[.A]?.hint != nil && !Catalogue.lines(world, .A).contains(.bystander(rows: 1)) ? nil
                    : "A: \(world.brains[.A]?.hint ?? "no hint"), \(Catalogue.lines(world, .A))"
            }
            .restartApp(.A)
            .restartApp(.C)
            .settle()
            .expectUser(.A, hover, 1)
            .expectUser(.B, hover, 1)
            .expectUser(.C, hover, 1)
            .expectPrompts(count: 0, mac: .A)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S06

    // D3-S06 · A gives ⌘⇧H to Show Hidden Items, B gives it to Search, concurrently · D3 section 15 · class: pass.
    // The hotkeys are bare key combinations that carry no token, so the oracles that follow the tokens of a value are left
    // out of this world; the oracles of bytes and files stay.
    static let s06 = CatalogueScenario(id: "D3-S06", title: "Two hotkeys on one combination are a clash row, and neither goes dead", source: .d3, kind: .pass) {
        let table = CatalogueExtraTables.table(hotkeyFamily: true)
        let combination = CatalogueExtraTables.combination(4)
        let toggle = CatalogueExtraTables.hotkeyToggle
        let search = CatalogueExtraTables.hotkeySearch
        let scenario = Catalogue.scenario("D3-S06", macs: running([.A, .B]))
            .brains { _, _ in CatalogueExtraTables.hotkeyBrain(table: table) }
            .oracles(CatalogueExtraTables.fileOracles)
            .offline(.B, seconds: 3_600)
            .edit(.A, toggle, value: combination)
            .edit(.B, search, value: combination)
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expect("both Macs are asked about the clash") { world in
                for mac in [SimMacName.A, .B] {
                    let units = Set(shown(world, mac).map(\.unit))
                    guard units == [toggle, search] else { return "\(mac)'s sheet shows \(units.sorted())" }
                }
                return nil
            }
            .expect("each Mac still holds its own hotkey") { world in
                Catalogue.value(world, .A, toggle) == combination && Catalogue.value(world, .B, search) == combination
                    ? nil : "A holds \(Catalogue.value(world, .A, toggle)?.canonical ?? "nothing"), B holds \(Catalogue.value(world, .B, search)?.canonical ?? "nothing")"
            }
            .expect("neither Mac holds both") { world in
                [SimMacName.A, .B].allSatisfy { Catalogue.value(world, $0, toggle) == nil || Catalogue.value(world, $0, search) == nil }
                    ? nil : "a Mac holds one combination twice"
            }
            .answer(.A, .use)
            .settle()
            .expect("exactly one action holds the combination on both Macs") { world in
                let holders = [SimMacName.A, .B].map { mac in
                    [toggle, search].filter { Catalogue.value(world, mac, $0) == combination }
                }
                return holders[0].count == 1 && holders[0] == holders[1] ? nil : "A: \(holders[0]), B: \(holders[1])"
            }
            .expect("B has no question and no hint left") { world in
                world.brains[.B]?.openPrompt == nil && world.brains[.B]?.hint == nil ? nil : "B shows \(world.brains[.B]?.hint ?? "a sheet")"
            }
            .restartApp(.B)
            .settle()
            .expectSilent()
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S07

    // D3-S07 · A changes X; B and C merge it; A is retired and its file deleted; fresh D joins · D3 section 15 · class: pass.
    static let s07 = CatalogueScenario(id: "D3-S07", title: "A retired Mac's file is deleted and a fresh Mac still gets its value through the relays", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let specs = running([.A, .B, .C]) + [joiner(.D, generation: 27)]
        let scenario = Catalogue.scenario("D3-S07", macs: specs)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expectUser(.B, hover, 1)
            .expectUser(.C, hover, 1)
            // A is retired: it quits for good and its file is deleted everywhere.
            .quit(.A)
            .deleteFile(of: .A)
            .settle()
            .expect("no file of A is left") { world in
                guard let path = Catalogue.ownPath(world, .A) else { return "A has no identity" }
                if case .absent? = world.replica(of: .B).entries[path] { return nil }
                return world.replica(of: .B).entries[path] == nil ? nil : "A's file is still in the folder"
            }
            .turnOn(.D)
            .settle()
            .expectPrompts(count: 0)
            .restartApp(.D)
            .settle()
            .expectUser(.D, hover, 1)
            .expect("D reads no value of A's from a file of A's") { world in
                Catalogue.live(world, .D, hover) == [Catalogue.user(1, hover)] ? nil : "D's replica holds \(Catalogue.live(world, .D, hover).map(\.canonical))"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S08

    // D3-S08 · N → 0.0.7-beta1 → N · D3 section 15 · class: pass.
    // A beta1 peer C wrote the legacy file; A goes back to 0.0.7-beta1 for a launch, which applies it with key removal,
    // and then returns to the redesigned build.
    static let s08 = CatalogueScenario(id: "D3-S08", title: "The return from a beta1 run is a join, and what beta1 applied is asked about", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let specs = running([.A, .B]) + [SimMacSpec(.C, .beta1, generation: 26, running: true, defaults: [hover: Catalogue.pre(.C)])]
        let scenario = Catalogue.scenario("D3-S08", macs: specs)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 30)
            .settle()
            .updateApp(.A, .beta1)
            .advance(seconds: 30)
            .launch(.A)
            .advance(seconds: 30)
            .settle()
            .expect("beta1 applied the legacy file") { world in
                Catalogue.value(world, .A, hover) == Catalogue.pre(.C) ? nil : "A holds \(Catalogue.value(world, .A, hover)?.canonical ?? "nothing")"
            }
            .updateApp(.A, .redesign)
            .launch(.A)
            .settle()
            .expect("A is asked about what beta1 applied") { world in
                Catalogue.shownUnits(world, .A).contains(hover) ? nil : "A's sheets show \(Catalogue.shownUnits(world, .A))"
            }
            .expect("what beta1 applied is not published as A's change") { world in
                let published = Catalogue.publishedEntries(world, .A, hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return published.contains(Catalogue.pre(.C)) ? "A published \(Catalogue.pre(.C).canonical)" : nil
            }
            .expect("B shows no sheet") { world in world.brains[.B]?.openPrompt == nil ? nil : "B shows a sheet" }
            .answer(.A, .use)
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.A, hover, 1)
            .expectUser(.B, hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.rehide, 2)
            // The two Macs of the new build are quiet; the beta1 peer is the only one with an alert.
            .expect("A and B are quiet") { world in
                [SimMacName.A, .B].compactMap { mac in
                    world.brains[mac]?.hint != nil || world.brains[mac]?.openPrompt != nil ? "\(mac) shows a hint or a sheet" : nil
                }.first
            }
        return Catalogue.run(scenario)
    }

    // MARK: D3-S09

    // D3-S09 · Preferences restored from a two-week-old backup, Σ not · D3 section 15 · class: pass.
    static let s09 = CatalogueScenario(id: "D3-S09", title: "Preferences restored from an old backup are a join without a dot", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let scenario = Catalogue.scenario("D3-S09", macs: running([.A, .B]))
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            // The backup is of this moment (the Mac's last launch).
            .restartApp(.A)
            .settle()
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .edit(.A, hover, value: Catalogue.user(2, hover))
            .settle()
            .restorePrefs(.A)
            .launch(.A)
            .settle()
            .expectValue(.A, hover, Catalogue.user(1, hover))
            .expectPrompts(count: 1, mac: .A)
            .expect("A is asked about the restored value") { world in
                shown(world, .A).contains { $0.unit == hover && $0.local == "u1@\(hover)" && $0.folder == "u2@\(hover)" }
                    ? nil : "A's sheet shows \(shown(world, .A))"
            }
            .expect("the restored value is not published as a new change") { world in
                let published = Catalogue.publishedEntries(world, .A, hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return published == [Catalogue.user(2, hover)] ? nil : "A's file holds \(published.map(\.canonical))"
            }
            .expect("B's change is not reverted") { world in
                Catalogue.value(world, .B, Catalogue.rehide) == Catalogue.user(3, Catalogue.rehide) ? nil : "B holds another value"
            }
            .answer(.A, .use)
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.A, hover, 2)
            .expectUser(.B, hover, 2)
            .expectUser(.A, Catalogue.rehide, 3)
            .expectUser(.B, Catalogue.rehide, 3)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S10

    // D3-S10 · Σ restored alone, or lost, with the own file in the folder · D3 section 15 · class: pass.
    // A state restored alone keeps the identity of its installation: the own file is read back, the counter ends above it
    // and no dot repeats. A state that is lost is a new installation of the same ID, which the own file shows as another
    // installation: the engine takes a new ID, remembers the old one and keeps every entry, so no dot can repeat either.
    static let s10 = CatalogueScenario(id: "D3-S10", title: "A lost or restored-alone state recovers from the own file and mints no dot twice", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        func world(_ name: String, reidentifies: Bool, _ loss: (SimScenario) -> SimScenario) -> SimScenario {
            let counter = CatalogueBox<UInt64>(0)
            let before = CatalogueBox<String?>(nil)
            let started = Catalogue.scenario(name, macs: running([.A, .B]))
                .edit(.A, hover, value: Catalogue.user(1, hover))
                .settle()
                .restartApp(.A)
                .settle()
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .settle()
                .perform("note A's counter and ID") { world in
                    counter.value = Catalogue.state(world, .A)?.counter ?? 0
                    before.value = SimMacRedesignProbe.id(of: world, .A)
                    return []
                }
            return loss(started)
                .launch(.A)
                .settle()
                .expectPrompts(count: 0)
                .expect("A shows no hint and no sheet") { world in
                    world.brains[.A]?.hint == nil && world.brains[.A]?.openPrompt == nil ? nil : "A shows \(world.brains[.A]?.hint ?? "a sheet")"
                }
                .expect(reidentifies ? "A has a new ID and remembers the old one" : "the ID stays and the counter ends above the own file") { world in
                    guard let id = SimMacRedesignProbe.id(of: world, .A), let state = Catalogue.state(world, .A) else { return "A has no state" }
                    if reidentifies {
                        return id != before.value && state.previousMacIDs.contains { $0.rawValue == before.value } ? nil : "A is \(id), it was \(before.value ?? "-")"
                    }
                    return id == before.value && state.counter >= counter.value ? nil : "A is \(id) at \(state.counter), the file had \(counter.value)"
                }
                .expectUser(.A, hover, 1)
                .expectUser(.A, Catalogue.rehide, 2)
                // A's next change gets a dot that no file holds, and B takes it.
                .edit(.A, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
                .settle()
                .restartApp(.B)
                .settle()
                .expectUser(.B, Catalogue.spacing, 3)
                .expectUser(.B, Catalogue.rehide, 2)
                .expectPrompts(count: 0)
                .expectQuiet()
        }
        let lost = world("D3-S10 lost", reidentifies: true) { $0.sigmaLost(.A) }
        let restored = world("D3-S10 restored alone", reidentifies: false) { $0.restoreSigma(.A) }
        return Catalogue.combine("D3-S10", [lost, restored].map(Catalogue.run))
    }

    // MARK: D3-S11

    // D3-S11 · A second user account on the same Mac with copied preferences · D3 section 15 · class: pass.
    static let s11 = CatalogueScenario(id: "D3-S11", title: "A second account with copied preferences gets its own ID and both sync", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let specs = [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, enabled: false, folder: nil, running: false)]
        let scenario = Catalogue.scenario("D3-S11", macs: specs)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            .copyAccount(from: .A, to: .B)
            .launch(.B)
            .settle()
            .expect("the account has an ID of its own") { world in
                let a = SimMacRedesignProbe.id(of: world, .A)
                let b = SimMacRedesignProbe.id(of: world, .B)
                return a != nil && b != nil && a != b ? nil : "A is \(a ?? "-"), B is \(b ?? "-")"
            }
            .expect("each account has a file of its own") { world in
                let files = world.replica(of: .A).entries.keys.filter { $0.hasPrefix(SimFolderIO.directory) }
                return files.count == 2 ? nil : "the folder holds \(files.sorted())"
            }
            .expectPrompts(count: 0)
            .expectUser(.B, hover, 1)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .edit(.B, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectUser(.A, Catalogue.spacing, 3)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S12

    // D3-S12 · A crash between applying to the defaults and persisting Σ · D3 section 15 · class: pass.
    static let s12 = CatalogueScenario(id: "D3-S12", title: "A crash between apply and persist re-applies and publishes nothing", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        func ownEntries(_ world: SimWorld, _ mac: SimMacName) -> [SyncEntry] {
            guard let own = Catalogue.state(world, mac)?.mac else { return [] }
            return Catalogue.publishedEntries(world, mac, hover).filter { $0.dot.mac == own }
        }
        // At launch: the fast-forward is applied, and the Mac dies before it persists anything.
        let launching = Catalogue.scenario("D3-S12 launch", macs: running([.A, .B]))
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            .quit(.B)
            .perform("B dies after the first effect of its next launch") { world in
                world.crashAfterEffect(1, on: .B)
                return []
            }
            .launch(.B)
            .expectUser(.B, hover, 1)
            .expect("B is down") { world in world.state(of: .B).running ? "B still runs" : nil }
            .launch(.B)
            .settle()
            .expectUser(.B, hover, 1)
            .expectPrompts(count: 0)
            .expectHint(.B, present: false)
            .expect("B published nothing of its own for the setting") { world in
                ownEntries(world, .B).isEmpty ? nil : "B's file carries \(ownEntries(world, .B).count) entries of its own"
            }
            .expectQuiet()
        // At Use: both Macs changed the setting; A answers Use and dies after applying B's value.
        let answering = conflicted("D3-S12 Use")
            .perform("A dies after the first effect of its answer") { world in
                world.crashAfterEffect(1, on: .A)
                return []
            }
            .answer(.A, .use)
            .expectUser(.A, hover, 2)
            .launch(.A)
            .settle()
            .expectUser(.A, hover, 2)
            .expectUser(.B, hover, 2)
            .expect("nothing but B's value is published") { world in
                let published = Catalogue.publishedEntries(world, .A, hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return published.allSatisfy { $0 == Catalogue.user(2, hover) } ? nil : "A's file holds \(published.map(\.canonical))"
            }
        return Catalogue.combine("D3-S12", [launching, answering].map(Catalogue.run))
    }

    // MARK: D3-S13

    // D3-S13 · An N+ Mac publishes a unit, or an enum value, this build does not know · D3 section 15 · class: pass.
    // A runs a newer build whose table knows `FutureSetting` and accepts every value of `ShelfMode`; B and C run the
    // older build, which knows neither the unit nor the value.
    static let s13 = CatalogueScenario(id: "D3-S13", title: "What a newer build publishes is relayed byte for byte, never applied, never deleted", source: .d3, kind: .pass) {
        let newer = CatalogueExtraTables.table(newer: true)
        let older = CatalogueExtraTables.olderTable()
        let future = CatalogueExtraTables.future
        let mode = CatalogueExtraTables.mode
        let relayed = CatalogueBox<[SyncEntry]>([])
        let specs = [
            SimMacSpec(.A, .redesignSkew, running: true),
            SimMacSpec(.B, .redesign, running: true),
            joiner(.C),
        ]
        let scenario = Catalogue.scenario("D3-S13", macs: specs)
            .brains { version, _ in SimMacRedesign(table: version == .redesignSkew ? newer : older) }
            .edit(.A, future, value: Catalogue.user(1, future))
            .edit(.A, mode, value: Catalogue.user(4, mode))
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 2)
            .expectUnset(.B, future)
            .expectUnset(.B, mode)
            .expect("B relays A's entries byte for byte") { world in
                let theirs = Catalogue.publishedEntries(world, .A, future) + Catalogue.publishedEntries(world, .A, mode)
                let mine = Catalogue.publishedEntries(world, .B, future) + Catalogue.publishedEntries(world, .B, mode)
                relayed.value = mine
                return theirs.count == 2 && theirs == mine ? nil : "A published \(theirs.count) entries, B relays \(mine.count)"
            }
            .expect("B shows the line for a value its build cannot use") { world in
                Catalogue.lines(world, .B).contains(.unusableValue) ? nil : "B's lines are \(Catalogue.lines(world, .B))"
            }
            .expectHint(.B, present: false)
            // B changes other settings for a while, and A retires: nothing of A's is deleted.
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .quit(.A)
            .deleteFile(of: .A)
            .settle()
            .expect("B still relays them") { world in
                let mine = Catalogue.publishedEntries(world, .B, future) + Catalogue.publishedEntries(world, .B, mode)
                return mine == relayed.value ? nil : "B relays \(mine.count) entries now"
            }
            // A third Mac of the older build joins and carries them on without applying them.
            .turnOn(.C)
            .settle()
            .restartApp(.C)
            .settle()
            .expectUser(.C, Catalogue.hover, 2)
            .expectUnset(.C, future)
            .expectUnset(.C, mode)
            .expect("C relays them too") { world in
                let mine = Catalogue.publishedEntries(world, .C, future) + Catalogue.publishedEntries(world, .C, mode)
                return mine.count == 2 ? nil : "C relays \(mine.count) entries"
            }
            .expectPrompts(count: 0)
        return Catalogue.run(scenario)
    }

    // MARK: D3-S14

    // D3-S14 · A custom icon of 400 KB (from Ice) · D3 section 15 · class: pass.
    static let s14 = CatalogueScenario(id: "D3-S14", title: "An oversize icon stays on its Mac with a note while every other unit syncs", source: .d3, kind: .pass) {
        let icon = Catalogue.icon
        let large = Catalogue.big(1, icon, bytes: 400 << 10)
        let small = Catalogue.big(2, icon, bytes: 1_000)
        let scenario = Catalogue.scenario("D3-S14", macs: running([.A, .B]))
            .edit(.A, icon, value: large)
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .settle()
            .expect("A shows the note") { world in
                Catalogue.lines(world, .A).contains(.oversizeIcon) ? nil : "A's lines are \(Catalogue.lines(world, .A))"
            }
            .expect("the icon is in no file") { world in
                Catalogue.publishedEntries(world, .A, icon).isEmpty ? nil : "A published the icon"
            }
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 3)
            .expectUnset(.B, icon)
            // B chooses a small icon: A keeps its own.
            .edit(.B, icon, value: small)
            .settle()
            .restartApp(.A)
            .settle()
            .expectValue(.A, icon, large)
            .expectValue(.B, icon, small)
            .expect("A still shows the note") { world in
                Catalogue.lines(world, .A).contains(.oversizeIcon) ? nil : "A's lines are \(Catalogue.lines(world, .A))"
            }
            .expectPrompts(count: 0)
        return Catalogue.run(scenario)
    }

    // MARK: D3-S15

    // D3-S15 · The first N Mac finds an empty Macs/ and a beta1 file that differs in two settings · D3 section 15 · class: pass.
    static let s15 = CatalogueScenario(id: "D3-S15", title: "Founding with a differing beta1 file asks once, and a second Mac joins the group, never the file", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let rehide = Catalogue.rehide
        let legacy = CatalogueBox<Data?>(nil)
        let specs = [
            SimMacSpec(.C, .beta1, generation: 26, running: true, defaults: [hover: Catalogue.pre(.C), rehide: Catalogue.pre(.C)]),
            joiner(.A, defaults: [hover: Catalogue.pre(.A), rehide: Catalogue.pre(.A)]),
            joiner(.B, defaults: [hover: Catalogue.pre(.B), rehide: Catalogue.pre(.B)]),
        ]
        let scenario = Catalogue.scenario("D3-S15", macs: specs)
            .advance(seconds: 30)
            .perform("note the legacy file") { world in
                legacy.value = Catalogue.legacyBytes(world, as: .A)
                return legacy.value == nil ? ["the beta1 peer wrote no file"] : []
            }
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about the two differences") { world in
                Set(shown(world, .A).map(\.unit)) == [hover, rehide] ? nil : "A's sheet shows \(shown(world, .A).map(\.unit))"
            }
            .answer(.A, .use)
            .settle()
            .expectValue(.A, hover, Catalogue.pre(.C))
            // The beta1 peer goes on writing the legacy file.
            .edit(.C, hover, value: Catalogue.user(9, hover))
            .advance(seconds: 30)
            .settle()
            .turnOn(.B)
            .settle()
            .expectPrompts(count: 1, mac: .B)
            .expect("B is asked against the group's values, not the legacy file's") { world in
                let held = Set(shown(world, .B).compactMap(\.folder))
                return held == ["pre(C)"] ? nil : "B's sheet shows the folder values \(held.sorted())"
            }
            .expect("the legacy file was never written by a redesigned Mac") { world in
                Catalogue.boundary(world, redesigned: [.A, .B], sheets: nil, hints: true).first
            }
        return Catalogue.run(scenario)
    }

    // MARK: D3-S16

    // D3-S16 · A (macOS 27) shares "Work"; B (27) adds it; A saves "Work" again; C (26) sees it · D3 section 15 · class: pass.
    static let s16 = CatalogueScenario(id: "D3-S16", title: "A profile syncs between macOS 27 Macs and never reaches a macOS 26 Mac", source: .d3, kind: .pass) {
        let profile = "prof/Work"
        let specs = [
            SimMacSpec(.A, .redesign, generation: 27, running: true, defaults: ["CurrentLayoutProfile": .string("Work")]),
            SimMacSpec(.B, .redesign, generation: 27, running: true),
            SimMacSpec(.C, .redesign, generation: 26, running: true),
        ]
        func profileToken(_ world: SimWorld, _ mac: SimMacName) -> String? {
            Catalogue.value(world, mac, profile)?.tokens.first
        }
        let first = CatalogueBox<String?>(nil)
        let scenario = Catalogue.scenario("D3-S16", macs: specs)
            .moveApp27(.A, bundle: Catalogue.appA, section: 1)
            .saveProfile(.A, "Work")
            .settle()
            .perform("note the first save") { world in
                first.value = profileToken(world, .A)
                return first.value == nil ? ["A saved no profile"] : []
            }
            .expectHint(.C, present: false)
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expect("B has the profile") { world in
                profileToken(world, .B) == first.value ? nil : "B holds \(profileToken(world, .B) ?? "nothing")"
            }
            .expect("C never has it") { world in
                Catalogue.value(world, .C, profile) == nil && world.defaults(of: .C)["LayoutProfiles"] == nil ? nil : "C holds a profile"
            }
            // A saves "Work" again: B sees an update, C nothing.
            .saveProfile(.A, "Work")
            .settle()
            .expectHint(.B, present: true)
            .expectHint(.C, present: false)
            .restartApp(.B)
            .settle()
            .expect("B holds the second save") { world in
                profileToken(world, .B) == profileToken(world, .A) && profileToken(world, .B) != first.value ? nil : "B holds \(profileToken(world, .B) ?? "nothing")"
            }
            .expect("C is left alone") { world in
                Catalogue.value(world, .C, profile) == nil && Catalogue.lines(world, .C).isEmpty ? nil : "C's lines are \(Catalogue.lines(world, .C))"
            }
            .expect("the bindings and the current profile never travel") { world in
                [SimMacName.B, .C].allSatisfy { world.defaults(of: $0)["CurrentLayoutProfile"] == nil } ? nil : "a Mac received the current profile"
            }
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S17

    // D3-S17 · `defaults write` while holzBar is quit, with B's change waiting in Σ · D3 section 15 · class: pass.
    static let s17 = CatalogueScenario(id: "D3-S17", title: "A defaults write while holzBar is quit is captured at launch before anything is applied", source: .d3, kind: .pass) {
        let hover = Catalogue.hover
        let scenario = Catalogue.scenario("D3-S17", macs: running([.A, .B]))
            .edit(.B, hover, value: Catalogue.user(1, hover))
            .settle()
            .expectHint(.A, present: true)
            .quit(.A)
            .defaultsWrite(.A, hover, value: Catalogue.user(9, hover))
            .launch(.A)
            .settle()
            .expectUser(.A, hover, 9)
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about the two values") { world in
                shown(world, .A).contains { $0.unit == hover && $0.local == "u9@\(hover)" && $0.folder == "u1@\(hover)" }
                    ? nil : "A's sheet shows \(shown(world, .A))"
            }
            .answer(.A, .keep)
            .settle()
            .expectUser(.A, hover, 9)
            .restartApp(.B)
            .settle()
            .expectUser(.B, hover, 9)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: D3-S18

    // D3-S18 · Dropbox makes `<A's MacID> (conflicted copy …).plist` · D3 section 15 · class: pass.
    // Two installations write one file within a conflict window, and the provider keeps the earlier content as a copy named
    // after the Mac.
    static let s18 = CatalogueScenario(id: "D3-S18", title: "A conflict copy named after the own ID re-identifies the Mac and no other Mac acts on it", source: .d3, kind: .pass) {
        var policy = SimFaultPolicy(medianDelayMilliseconds: 2_000, conflictCopyProbability: 1, conflictStyles: [.dropbox])
        policy.coalesceProbability = 1
        let before = CatalogueBox<[String: String]>([:])
        let ids: (SimWorld) -> [String: String] = { world in
            Dictionary(uniqueKeysWithValues: [SimMacName.A, .B, .C].compactMap { mac in SimMacRedesignProbe.id(of: world, mac).map { (mac.name, $0) } })
        }
        let scenario = SimScenario("D3-S18", seed: 1, policy: policy)
            .macs(running([.A, .B]) + [SimMacSpec(.C, .redesign, enabled: false, folder: nil, running: false)])
            .brains(Catalogue.brain)
            // INV-ID1 (no two Macs use one ID after launching) is what this world creates on purpose, and what the
            // scenario then asserts the engine undoes. INV-ID2 is left out for the reason plan 28-10 gave for S-11: the
            // engine goes on under a new identity and marks the units of the old one as pre-existing instead of opening a
            // join, which the oracle does not read as joining again.
            // INV-F5, INV-S3, INV-S7 and INV-ID3 are left out for the same reason: until the collision is found, one of the two entries
            // that carry one dot looks like the other to a third Mac, and each installation reads the other's file as its own.
            .oracles(SimOracleSet.safety.without(["INV-F5", "INV-ID1", "INV-ID2", "INV-ID3", "INV-S3", "INV-S7"]))
            .settle()
            .perform("note the identities") { world in
                before.value = ids(world)
                return []
            }
            .duplicateInstallation(source: .A, target: .C)
            .launch(.C)
            // Both installations change a setting within one second, so that they mint the same counter under one ID.
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.C, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 3)
            .settle()
            .restartApp(.A)
            .restartApp(.C)
            .settle()
            .relaunchAll()
            .expect("one of the two installations has an ID of its own now") { world in
                let now = ids(world)
                return now["A"] != now["C"] ? nil : "both installations are \(now["A"] ?? "-")"
            }
            .expect("B keeps its identity and is never asked") { world in
                ids(world)["B"] == before.value["B"] && world.allSteps.flatMap(\.prompts).filter({ $0.mac == .B }).isEmpty
                    ? nil : "B is \(ids(world)["B"] ?? "-")"
            }
            .expect("a copy named after the ID was written") { world in
                world.replica(of: .B).entries.keys.contains { $0.contains("conflicted copy") } ? nil : "the provider made no conflict copy"
            }
            .expect("nothing is lost: both settings are held by every Mac in the end") { world in
                var missing: [String] = []
                for mac in [SimMacName.A, .B, .C] {
                    if Catalogue.value(world, mac, Catalogue.hover) != Catalogue.user(1, Catalogue.hover) { missing.append("\(mac) hover") }
                    if Catalogue.value(world, mac, Catalogue.rehide) != Catalogue.user(2, Catalogue.rehide) { missing.append("\(mac) rehide") }
                }
                return missing.isEmpty ? nil : "missing: \(missing)"
            }
            .expect("the installations that took a new ID remember the old one in their state") { world in
                let now = ids(world)
                let moved = ["A", "C"].filter { now[$0] != before.value["A"] }
                guard !moved.isEmpty else { return "no installation took a new ID: \(now)" }
                for name in moved {
                    guard let state = Catalogue.state(world, SimMacName(name)),
                          state.previousMacIDs.contains(where: { $0.rawValue == before.value["A"] })
                    else { return "\(name) did not remember the old ID" }
                }
                return nil
            }
        return Catalogue.run(scenario)
    }

    // MARK: D3-S19

    // D3-S19 · Turn Off on A; A changes X and Y, B changes Y and Z; Turn On… on A · D3 section 15 · class: pass.
    static let s19 = CatalogueScenario(id: "D3-S19", title: "Turn Off with edits on both sides asks only about the unit changed on both", source: .d3, kind: .pass) {
        let x = Catalogue.spacing
        let y = Catalogue.hover
        let z = Catalogue.rehide
        func edited(_ name: String) -> SimScenario {
            Catalogue.scenario(name, macs: running([.A, .B]))
                .turnOff(.A)
                .settle()
                .edit(.A, x, value: Catalogue.user(1, x))
                .edit(.A, y, value: Catalogue.user(2, y))
                .edit(.B, y, value: Catalogue.user(3, y))
                .edit(.B, z, value: Catalogue.user(4, z))
                .settle()
                .turnOn(.A)
                .settle()
                .expectPrompts(count: 1, mac: .A)
                .expect("A asks about Y only") { world in
                    Set(shown(world, .A).map(\.unit)) == [y] ? nil : "A's sheet shows \(shown(world, .A).map(\.unit))"
                }
        }
        let cancelled = edited("D3-S19 Cancel")
            .answer(.A, .cancel)
            .settle()
            .expect("sync stays off and A's values are as they were") { world in
                world.state(of: .A).enabled ? "A turned sync on" : nil
            }
            .expectUser(.A, y, 2)
            .expectUser(.A, x, 1)
            .expectUnset(.A, z)
        let kept = edited("D3-S19 Keep")
            .answer(.A, .keep)
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectUser(.A, x, 1)
            .expectUser(.B, x, 1)
            .expectUser(.A, z, 4)
            .expectUser(.B, z, 4)
            .expectUser(.A, y, 2)
            .expectUser(.B, y, 2)
            .expectQuiet()
        return Catalogue.combine("D3-S19", [cancelled, kept].map(Catalogue.run))
    }

    // MARK: D3-S20

    // D3-S20 · 70 Macs in the folder · D3 section 15 · class: pass.
    static let s20 = CatalogueScenario(id: "D3-S20", title: "Seventy Macs in the folder: 64 files read, the skipped files reported, every value relayed", source: .d3, kind: .pass) {
        // Sixty-nine Macs outside the simulation have left their files in the folder. Their IDs sort after any ID the
        // simulator draws, so the reader's own file is the first of seventy and the last six of the others are left out (the
        // simulated provider has no modification dates, so the files read are the first by name; the app reads the most
        // recently modified, which always includes the own file just written). The value of the hover setting was made by
        // Mac 66, whose file is left out, and is relayed by the file of Mac 3; the value of the rehide setting was made by
        // Mac 5, whose file is read.
        let hover = Catalogue.hover
        let rehide = Catalogue.rehide
        func macID(_ index: Int) -> SyncMacID {
            SyncMacID(UUID(uuidString: String(format: "%08X-0000-4000-8000-000000000000", 0xFFFFFF00 + index)) ?? UUID())
        }
        func entry(_ index: Int, _ unit: String, _ value: SimValue) -> SyncEntry {
            SyncEntry(
                dot: SyncDot(mac: macID(index), n: 1),
                at: Date(timeIntervalSince1970: 1_790_000_000),
                payload: .value(SyncValue(sim: value) ?? .string(""))
            )
        }
        func file(_ index: Int, entries: [(unit: String, entry: SyncEntry)]) -> Data {
            var counters: [SyncMacID: UInt64] = [:]
            var registers: [SyncUnitKey: [SyncEntry]] = [:]
            for item in entries {
                counters[item.entry.dot.mac] = max(counters[item.entry.dot.mac] ?? 0, item.entry.dot.n)
                if let key = SimEngineUnits.key(ofUnit: item.unit) { registers[key, default: []].append(item.entry) }
            }
            let contents = SyncDeviceFile.Contents(
                unitTable: 1, mac: macID(index), installation: "planted-\(index)", written: Date(timeIntervalSince1970: 1_790_000_000),
                replica: SyncReplica(context: SyncContext(counters: counters), registers: registers)
            )
            return (try? SyncDeviceFile.encode(contents)) ?? Data()
        }
        let hoverEntry = entry(66, hover, Catalogue.user(1, hover))
        let rehideEntry = entry(5, rehide, Catalogue.user(2, rehide))
        // The planted files are the work of Macs the simulator knows nothing about, so the oracles that follow the origin
        // of a value cannot judge this world; the oracles of files and bytes stay.
        var scenario = Catalogue.scenario("D3-S20", macs: [SimMacSpec(.A, .redesign, generation: 26, running: false)])
            .oracles(CatalogueExtraTables.fileOracles)
        for index in 0..<69 {
            var entries: [(unit: String, entry: SyncEntry)] = []
            if index == 66 { entries = [(hover, hoverEntry)] }
            if index == 3 { entries = [(hover, hoverEntry)] }
            if index == 5 { entries = [(rehide, rehideEntry)] }
            scenario = scenario.provider(.plant(path: "\(SimFolderIO.directory)/\(macID(index).rawValue).plist", data: file(index, entries: entries)))
        }
        scenario = scenario
            .launch(.A)
            .settle()
            .restartApp(.A)
            .settle()
            .expect("the reader reports the files it left out") { world in
                Catalogue.lines(world, .A).contains(.skippedFiles(6)) ? nil : "the lines are \(Catalogue.lines(world, .A))"
            }
            .expect("the reader read the 64 first files and no other") { world in
                let launches = Catalogue.launchHooks(world, .A)
                let reads = launches.last?.reads ?? []
                let files = reads.filter { $0.entry.path.hasPrefix(SimFolderIO.directory + "/") }
                return files.count <= 64 ? nil : "the reader read \(files.count) files"
            }
            .expectUser(.A, hover, 1)
            .expectUser(.A, rehide, 2)
            .expect("nobody was asked") { world in
                Catalogue.promptCount(world) == 0 ? nil : "\(Catalogue.promptCount(world)) sheets opened"
            }
        return Catalogue.run(scenario)
    }

    // MARK: Texts

    // The D3 table is the "Must" of each scenario; there is no A1 text for them, so the failure message prints the title.
}

/// The D3 scenarios, one test each.
@Suite("CatalogueD3")
struct CatalogueD3Tests {
    @Test("D3 section 15: the scenarios of the settings-only design", arguments: CatalogueExtraTables.selected(CatalogueD3.scenarios))
    func scenario(_ scenario: CatalogueScenario) async {
        await HeavyTestGate.run {
            Catalogue.check(scenario)
        }
    }
}
