//
//  CatalogueG6FileFaults.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G6 of the A1 regression catalogue (S-34 to S-44): the file goes missing, is restored or becomes unusable. Every
/// fault is one of the provider's own operations (delete, deleteFolder, restore, a foreign file in place of the
/// file); no scenario edits a Mac's state directly. The redesigned build has one file per Mac, so "the file goes
/// missing" names the file of the Mac whose change was lost, and a Mac heals its own file from its state.
nonisolated enum CatalogueG6FileFaults {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = [s34, s35, s36]
        all += s37
        all += s38
        all.append(s39)
        all += s40
        all += s41
        all += s42
        all += [s43, s44]
        return all
    }()

    // MARK: Building blocks

    /// A Mac's own arrangement entry in the file it wrote last: the dots of its own that list the arrangement.
    static func ownListed(_ world: SimWorld, _ mac: SimMacName, _ unit: String) -> [SyncEntry] {
        guard let own = Catalogue.state(world, mac)?.mac else { return [] }
        return Catalogue.publishedEntries(world, mac, unit).filter { $0.dot.mac == own }
    }

    /// Every running Mac holds the value `box` noted at the unit.
    static func everyMacHolds(_ scenario: SimScenario, _ unit: String, _ box: CatalogueBox<SimValue?>, label: String) -> SimScenario {
        scenario.expect(label) { world in
            // A macOS 26 Mac has no arrangement of the macOS 27 families; it only relays them.
            let different = world.macs.keys.sorted().filter {
                world.macs[$0]?.running == true && !(unit.hasPrefix("l27/") && world.macs[$0]?.generation == 26) && Catalogue.value(world, $0, unit) != box.value
            }
            return different.isEmpty ? nil : "\(different) do not hold \(box.value?.canonical ?? "nothing") at \(unit)"
        }
    }

    /// Remembers a Mac's value of a unit now.
    static func note(_ scenario: SimScenario, _ mac: SimMacName, _ unit: String, in box: CatalogueBox<SimValue?>) -> SimScenario {
        scenario.perform("note \(mac)'s \(unit)") { world in
            box.value = Catalogue.value(world, mac, unit)
            return []
        }
    }

    // MARK: S-34

    // S-34 · A write over a missing file reverts another Mac's change · A1 G6 · class: pass · source: V2-#2, V3-#1a (RC-1, RC-3).
    static let s34 = CatalogueScenario(id: "S-34", title: "A write over a missing file reverts nobody", source: .a1, kind: .pass) {
        // B changes a setting; before A reads it the file goes (deleted, or damaged), A changes another setting.
        func lost(_ name: String, loss: (SimScenario) -> SimScenario) -> SimScenario {
            loss(
                Catalogue.scenario(name, macs: CatalogueG1Joining.pairSpecs())
                    .settle()
                    .offline(.A, seconds: 3_600)
                    .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                    .advance(seconds: 30)
            )
            .online(.A)
            .advance(seconds: 30)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 60)
            // B checks: its change is still B's, nothing was applied over it, and nobody was silently reverted.
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
        }
        let deleted = lost("S-34 deleted") { $0.deleteFile(of: .B) }
            .settle()
            .expectFile(of: .B)
            .expectUser(.B, Catalogue.hover, 1)
            .relaunchAll()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        // A damaged file is never written over: B goes on under a file of its own after ten minutes and loses nothing.
        let damaged = lost("S-34 damaged") { $0.foreignFile(of: .B, .truncatedPlist) }
            .oracles(SimOracleSet.safety.without(["INV-ID2"]))
            .advance(seconds: 700)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .relaunchAll()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectQuiet()
        return Catalogue.combine("S-34", [deleted, damaged].map(Catalogue.run))
    }

    // MARK: S-35

    // S-35 · A waiting version dropped when the file goes away · A1 G6 · class: pass · source: V3-#1a' (RC-9, RC-3).
    static let s35 = CatalogueScenario(id: "S-35", title: "A waiting version survives the loss of the file", source: .a1, kind: .pass) {
        func scenario(_ name: String, loss: (SimScenario) -> SimScenario) -> SimScenario {
            loss(
                Catalogue.scenario(name, macs: CatalogueG1Joining.pairSpecs())
                    .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                    .settle()
                    .expectHint(.A, present: true)
            )
            .advance(seconds: 60)
            .expectHint(.A, present: true)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 60)
            .expectHint(.A, present: true)
            .expect("B's entry is still waiting on A") { world in
                let live = Catalogue.live(world, .A, Catalogue.hover)
                return live == [Catalogue.user(1, Catalogue.hover)] ? nil : "A's replica holds \(live.map(\.canonical)) for \(Catalogue.hover)"
            }
            .expect("A published no entry of its own for the waiting unit") { world in
                ownListed(world, .A, Catalogue.hover).isEmpty ? nil : "A's file carries an entry of its own for \(Catalogue.hover)"
            }
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .relaunchAll()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.hover, 1)
        }
        let deleted = scenario("S-35 deleted") { $0.deleteFile(of: .B) }
        let folder = scenario("S-35 folder deleted") { $0.provider(.deleteFolder()) }
        let damaged = scenario("S-35 damaged") { $0.foreignFile(of: .B, .garbage) }
            .oracles(SimOracleSet.safety.without(["INV-ID2"]))
        return Catalogue.combine("S-35", [deleted, folder, damaged].map(Catalogue.run))
    }

    // MARK: S-36

    // S-36 · A relaunch while the file is missing · A1 G6 · class: pass · source: V4, step AJ (RC-9).
    static let s36 = CatalogueScenario(id: "S-36", title: "A waiting version survives a relaunch with the file missing", source: .a1, kind: .pass) {
        let scenario = Catalogue.scenario("S-36", macs: CatalogueG1Joining.pairSpecs())
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .expectHint(.A, present: true)
            .deleteFile(of: .B)
            .advance(seconds: 30)
            // Quit and reopen A while the file is missing.
            .quit(.A)
            .launch(.A)
            .advance(seconds: 30)
            .expect("B's version is still on A after the relaunch") { world in
                let live = Catalogue.live(world, .A, Catalogue.hover)
                return live.contains(Catalogue.user(1, Catalogue.hover)) ? nil : "A's replica holds \(live.map(\.canonical)) for \(Catalogue.hover)"
            }
            .expect("B's version is applied or still offered") { world in
                Catalogue.value(world, .A, Catalogue.hover) == Catalogue.user(1, Catalogue.hover) || world.brains[.A]?.hint != nil
                    ? nil : "A shows no hint and holds \(Catalogue.value(world, .A, Catalogue.hover)?.canonical ?? "nothing")"
            }
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .relaunchAll()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: S-37

    /// B arranges and changes a setting while A, without touching its arrangement, changes it the other way; A answers
    /// Keep. In the generation-27 form A holds an automatic placement of its own, which must never be promoted over B's
    /// intent; in the generation-26 form the arrangement is a local key that never syncs.
    static func keptWorld(_ name: String, generation: Int, arrangement: CatalogueBox<SimValue?>) -> SimScenario {
        askedWorld(name, generation: generation, arrangement: arrangement)
            .answer(.A, .keep)
            .settle()
            .expectUser(.A, Catalogue.hover, 2)
    }

    /// The same world up to the moment A's sheet is open.
    static func askedWorld(_ name: String, generation: Int, arrangement: CatalogueBox<SimValue?>) -> SimScenario {
        var scenario = Catalogue.scenario(name, macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
        if generation == 27 { scenario = scenario.placeNewApp27(.A, bundle: Catalogue.appA) }
        scenario = scenario.settle().offline(.A, seconds: 3_600)
        scenario = CatalogueG3Generations.arrange(scenario, .B, generation: generation, section: 1, k: 1)
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 30)
        return note(scenario, .B, generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry, in: arrangement)
            .online(.A)
            .settle()
            .expect("A is asked about the setting") { world in
                world.brains[.A]?.openPrompt?.shown.map(\.unit).contains(Catalogue.hover) == true ? nil : "A's sheet shows \(Catalogue.shownUnits(world, .A))"
            }
    }

    /// What every form of S-37 and S-38 ends with: the arrangement of B on every Mac that shares one, no arrangement
    /// question, the setting A kept.
    static func keptEnd(_ scenario: SimScenario, generation: Int, arrangement: CatalogueBox<SimValue?>, drag: Int) -> SimScenario {
        var checked = CatalogueG3Generations.common(scenario.relaunchAll(), generation: generation, drags: [.B: drag])
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
        if generation == 27 {
            checked = everyMacHolds(checked, Catalogue.layoutA, arrangement, label: "every Mac holds B's arrangement")
        }
        return checked.expectQuiet()
    }

    // S-37 · Keep without a layout edit, then the file goes away · A1 G6 · class: scope · source: V3-#1b (RC-3, RC-5, RC-8).
    static let s37: [CatalogueScenario] = [
        CatalogueScenario(id: "S-37/26", title: "Keep, then the loss of the file, touches no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS37(generation: 26)
        },
        CatalogueScenario(id: "S-37/27", title: "Keep, then the loss of the file, never promotes A's placement over B's (generation 27)", source: .a1, kind: .scope) {
            runS37(generation: 27)
        },
    ]

    private static func runS37(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        let scenario = keptWorld("S-37", generation: generation, arrangement: arrangement)
            // The file is deleted, and A changes a setting that is no arrangement.
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            // B is quit and reopened.
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 3)
        return Catalogue.run(keptEnd(scenario, generation: generation, arrangement: arrangement, drag: 1))
    }

    // MARK: S-38

    // S-38 · A copy over a missing file, then a second write · A1 G6 · class: scope · source: V4, step AE (RC-5, RC-3).
    static let s38: [CatalogueScenario] = [
        CatalogueScenario(id: "S-38/26", title: "Two writes over a missing file touch no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS38(generation: 26)
        },
        CatalogueScenario(id: "S-38/27", title: "Two writes over a missing file never promote A's placement (generation 27)", source: .a1, kind: .scope) {
            runS38(generation: 27)
        },
    ]

    private static func runS38(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        let later = CatalogueBox<SimValue?>(nil)
        var scenario = keptWorld("S-38", generation: generation, arrangement: arrangement)
            // The file is deleted. A changes the setting, then changes it back: two writes.
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .advance(seconds: 30)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .settle()
            // B is reopened and drags again.
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 2)
        scenario = CatalogueG3Generations.arrange(scenario, .B, generation: generation, section: 2, k: 2).settle()
        scenario = note(scenario, .B, generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry, in: later)
            .restartApp(.A)
            .settle()
        // B keeps the newest arrangement, and every Mac that shares one holds it.
        return Catalogue.run(keptEnd(scenario, generation: generation, arrangement: later, drag: 2))
    }

    // MARK: S-39

    // S-39 · Several writes, or a third Mac, on top of a version without B's change · A1 G6 · class: pass · source: V4, step AG (RC-1, RC-2).
    static let s39 = CatalogueScenario(id: "S-39", title: "However many writes follow a version without B's change, B's change survives", source: .a1, kind: .pass) {
        func trio(_ name: String) -> SimScenario {
            Catalogue.scenario(name, macs: CatalogueG3Generations.specs([.A, .B, .C], generation: 27))
                .settle()
                .offline(.A, seconds: 3_600)
                .offline(.C, seconds: 3_600)
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 30)
                .deleteFile(of: .B)
                .advance(seconds: 30)
                .online(.A)
                .online(.C)
                .advance(seconds: 30)
        }
        func end(_ scenario: SimScenario) -> SimScenario {
            scenario
                .expectUser(.B, Catalogue.hover, 1)
                .settle()
                .relaunchAll()
                .expectUser(.A, Catalogue.hover, 1)
                .expectUser(.B, Catalogue.hover, 1)
                .expectUser(.C, Catalogue.hover, 1)
                .expectPrompts(count: 0)
                .expectQuiet()
        }
        // A changes a setting, then another.
        let several = end(
            trio("S-39 several writes")
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 30)
                .edit(.A, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
                .advance(seconds: 30)
        )
        .expectUser(.B, Catalogue.rehide, 2)
        .expectUser(.C, Catalogue.spacing, 3)
        // A third Mac applies A's file and changes a setting.
        let descendant = end(
            trio("S-39 third Mac")
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 30)
                .restartApp(.C)
                .advance(seconds: 30)
                .edit(.C, Catalogue.menus, value: Catalogue.user(4, Catalogue.menus))
                .advance(seconds: 30)
        )
        .expectUser(.B, Catalogue.menus, 4)
        .expectUser(.A, Catalogue.menus, 4)
        return Catalogue.combine("S-39", [several, descendant].map(Catalogue.run))
    }

    // MARK: S-40

    // S-40 · A third Mac applies a version without a write it holds · A1 G6 · class: scope · source: V5, step AM (RC-1, RC-5).
    static let s40: [CatalogueScenario] = [
        CatalogueScenario(id: "S-40/26", title: "A third Mac applying a version without a write it holds keeps its own (generation 26)", source: .a1, kind: .scope) {
            runS40(generation: 26)
        },
        CatalogueScenario(id: "S-40/27", title: "A third Mac applying a version without a write it holds keeps the arrangement (generation 27)", source: .a1, kind: .scope) {
            runS40(generation: 27)
        },
    ]

    private static func runS40(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        let unit = generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry
        var scenario = Catalogue.scenario("S-40", macs: CatalogueG3Generations.specs([.A, .B, .C], generation: generation))
            .settle()
            .offline(.B, seconds: 3_600)
        // A arranges. Before B reads it, C restarts with it, then the file is deleted.
        scenario = CatalogueG3Generations.arrange(scenario, .A, generation: generation, section: 1, k: 1)
            .advance(seconds: 30)
            .restartApp(.C)
            .advance(seconds: 30)
        scenario = note(scenario, .A, unit, in: arrangement)
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .online(.B)
            .advance(seconds: 30)
            // B changes a setting: its write lacks A's. C checks.
            .edit(.B, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.C)
            .settle()
            .expectUser(.C, Catalogue.hover, 2)
        var end = CatalogueG3Generations.common(scenario.relaunchAll(), generation: generation, drags: generation == 26 ? [.A: 1] : [:])
            .expectUser(.A, Catalogue.hover, 2)
            .expectUser(.B, Catalogue.hover, 2)
            .expectQuiet()
        if generation == 27 {
            end = everyMacHolds(end, Catalogue.layoutA, arrangement, label: "every Mac keeps A's arrangement")
        }
        return Catalogue.run(end)
    }

    // MARK: S-41

    // S-41 · A context claims a write whose arrangement was never taken in · A1 G6 · class: scope · source: V5, step AN (RC-5, RC-3) [§5.2 pair 8].
    static let s41: [CatalogueScenario] = [
        CatalogueScenario(id: "S-41/26", title: "A context claims only what it has seen, no arrangement involved (generation 26)", source: .a1, kind: .scope) {
            runS41(generation: 26)
        },
        CatalogueScenario(id: "S-41/27", title: "A context never claims an arrangement that was not taken in (generation 27)", source: .a1, kind: .scope) {
            runS41(generation: 27)
        },
    ]

    private static func runS41(generation: Int) -> SimScenarioResult {
        let arrangement = CatalogueBox<SimValue?>(nil)
        // The S-38 steps 1 and 2, then B changes a setting and A restarts with it (A keeps its own arrangement).
        let scenario = keptWorld("S-41", generation: generation, arrangement: arrangement)
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .advance(seconds: 30)
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .settle()
            .edit(.B, Catalogue.spacing, value: Catalogue.user(5, Catalogue.spacing))
            .settle()
            .restartApp(.A)
            .settle()
            // The file goes away again and A changes a setting.
            .provider(.deleteFolder())
            .advance(seconds: 30)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(4, Catalogue.rehide))
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 4)
            .expectUser(.A, Catalogue.spacing, 5)
        return Catalogue.run(keptEnd(scenario, generation: generation, arrangement: arrangement, drag: 1))
    }

    // MARK: S-42

    // S-42 · A sync app restores an older version of this Mac's own · A1 G6 · class: scope · source: V2-#6 (RC-3, RC-5).
    static let s42: [CatalogueScenario] = [
        CatalogueScenario(id: "S-42/26", title: "A restored own version brings back no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS42(generation: 26)
        },
        CatalogueScenario(id: "S-42/27", title: "A restored own version never reverts A's newer arrangement (generation 27)", source: .a1, kind: .scope) {
            runS42(generation: 27)
        },
    ]

    private static func runS42(generation: Int) -> SimScenarioResult {
        let marked = CatalogueBox(-1)
        let arrangement = CatalogueBox<SimValue?>(nil)
        let unit = generation == 27 ? Catalogue.layoutA : Catalogue.sectionsEntry
        var scenario = Catalogue.scenario("S-42", macs: CatalogueG3Generations.specs([.A, .B], generation: generation))
            // 1. A changes a setting and writes; the copy is set aside.
            .edit(.A, Catalogue.rehide, value: Catalogue.user(1, Catalogue.rehide))
            .settle()
            .markFile(of: .A, in: marked)
        // 2. A drags and writes again.
        scenario = CatalogueG3Generations.arrange(scenario, .A, generation: generation, section: 1, k: 1).settle()
        scenario = note(scenario, .A, unit, in: arrangement)
            // 3. The copy is put back. 4. A quits and reopens. 5. A changes "Show on hover".
            .restoreFile(of: .A, to: marked)
            .settle()
            .restartApp(.A)
            .settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .settle()
            .expect("A keeps the drag") { world in
                Catalogue.value(world, .A, unit) == arrangement.value ? nil : "A holds \(Catalogue.value(world, .A, unit)?.canonical ?? "nothing") at \(unit)"
            }
            .relaunchAll()
            .expectUser(.B, Catalogue.hover, 3)
            .expectUser(.B, Catalogue.rehide, 1)
        scenario = CatalogueG3Generations.common(scenario, generation: generation, drags: generation == 26 ? [.A: 1] : [:])
        if generation == 27 {
            scenario = everyMacHolds(scenario, unit, arrangement, label: "every Mac holds A's drag")
                .expect("A's next write lists the dragged arrangement as current") { world in
                    let listed = Catalogue.publishedEntries(world, .A, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                    return listed == [arrangement.value].compactMap { $0 } ? nil : "A's file lists \(listed.map(\.canonical))"
                }
        }
        return Catalogue.run(scenario.expectQuiet())
    }

    // MARK: S-43

    // S-43 · Variants of an unusable file · A1 G6 · class: pass · source: V0-#1, V3-#1 (RC-3, RC-10).
    static let s43 = CatalogueScenario(id: "S-43", title: "An unusable file is refused whole, shown, never read as missing and never written over", source: .a1, kind: .pass) {
        // B's file becomes unusable after A has read it: a symbolic link, an oversize file, a truncated plist, a plist
        // of the wrong shape and bytes that are no plist at all (the empty file is refused the same way, asserted below).
        func variant(_ kind: SimForeignKind) -> SimScenarioResult {
            let path = CatalogueBox<String?>(nil)
            let writes = CatalogueBox(0)
            let scenario = Catalogue.scenario("S-43 \(kind.rawValue)", macs: CatalogueG1Joining.pairSpecs())
                .oracles(SimOracleSet.safety.without(["INV-ID2"]))
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
                .perform("note the file of B") { world in
                    path.value = Catalogue.ownPath(world, .B)
                    writes.value = Catalogue.writes(world, by: .B, path: path.value).count
                    return []
                }
                .foreignFile(of: .B, kind)
                .advance(seconds: 30)
                .restartApp(.A)
                .advance(seconds: 30)
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 60)
                .expect("A shows the unusable file as a status") { world in
                    Catalogue.lines(world, .A).contains(.unreadableFile) ? nil : "A shows \(Catalogue.lines(world, .A))"
                }
                .expect("A never reads the file as missing: B's version is still held") { world in
                    Catalogue.live(world, .A, Catalogue.hover).contains(Catalogue.user(1, Catalogue.hover)) ? nil : "A's replica lost B's entry"
                }
                .expect("nobody writes over the refused file") { world in
                    guard let path = path.value else { return "no file noted" }
                    let count = world.writeLog.filter { $0.path == path }.count
                    return count == writes.value ? nil : "the refused file was written \(count - writes.value) times"
                }
                .expectUser(.B, Catalogue.hover, 1)
                .expectUser(.A, Catalogue.rehide, 2)
                // Ten simulated minutes later B goes on under a new identity, and the Macs converge.
                .advance(seconds: 700)
                .restartApp(.B)
                .settle()
                .expect("B goes on under a file of its own (a link of no size never lasts: B keeps waiting)") { world in
                    if kind == .symbolicLink {
                        let count = world.writeLog.filter { $0.path == path.value }.count
                        return count == writes.value ? nil : "B wrote over the link"
                    }
                    return Catalogue.ownPath(world, .B) != path.value ? nil : "B still uses the refused path"
                }
                .relaunchAll()
                .expectUser(.A, Catalogue.hover, 1)
                .expectUser(.B, Catalogue.rehide, 2)
            return Catalogue.run(scenario)
        }
        let emptyRefused = Catalogue.scenario("S-43 empty file", macs: CatalogueG1Joining.pairSpecs())
            .expect("an empty file and a file without the settings are refused") { _ in
                if case .failure = SyncDeviceFile.decode(Data(), fileName: "x.plist") { nil } else { "an empty file was decoded" }
            }
        return Catalogue.combine("S-43", SimForeignKind.allCases.map(variant) + [Catalogue.run(emptyRefused)])
    }

    // MARK: S-44

    // S-44 · Setting up a new folder · A1 G6 · class: pass · source: R6 deviation (must not stall).
    static let s44 = CatalogueScenario(id: "S-44", title: "Change… to an empty folder publishes the whole state with no question", source: .a1, kind: .pass) {
        let specs = [
            SimMacSpec(.A, .redesign, generation: 27, running: true),
            SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, defaults: [Catalogue.hover: Catalogue.pre(.B)], syncedFolder: "F2"),
        ]
        let scenario = Catalogue.scenario("S-44", macs: specs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .moveApp27(.A, bundle: Catalogue.appA, section: 1)
            .settle()
            .checkpoint()
            .changeFolder(.A, folder: "F2")
            .settle()
            .expectPrompts(count: 0, mac: .A)
            .expect("A published its whole state, its arrangement listed as current") { world in
                var missing: [String] = []
                for unit in [Catalogue.hover, Catalogue.rehide, Catalogue.layoutA] where Catalogue.publishedEntries(world, .A, unit).isEmpty {
                    missing.append(unit)
                }
                return missing.isEmpty ? nil : "A's new file lacks \(missing)"
            }
            // Later B joins: S-01 and S-07, B asks about the setting it holds and takes the rest.
            .turnOn(.B, folder: "F2")
            .settle()
            .expectPrompts(count: 1, mac: .B)
            .answer(.B, .keep)
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectValue(.B, Catalogue.hover, Catalogue.pre(.B))
            .expectValue(.A, Catalogue.hover, Catalogue.pre(.B))
            .expectUser(.B, Catalogue.rehide, 2)
            .expect("B takes A's arrangement") { world in
                Catalogue.value(world, .B, Catalogue.layoutA) == Catalogue.value(world, .A, Catalogue.layoutA) && Catalogue.value(world, .B, Catalogue.layoutA) != nil
                    ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.layoutA)?.canonical ?? "nothing")"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-34": CatalogueText(
            setup: "A and B on N, same macOS version. Both last synced V1.",
            steps: "B changes \"Show on hover\" (V2). Before A reads it, the file is deleted or damaged. A changes another setting and writes. B checks.",
            wrong: "B sees A's newer version and has no changes, so it applies it silently at its next launch. B's own change is reverted.",
            must: "B asks, because its last change is missing, or the change is merged. Never a silent apply."
        ),
        "S-35": CatalogueText(
            setup: "B writes V2 and A shows Restart or Choose Settings… (V2 pending).",
            steps: "The file is deleted or damaged. A checks, or changes a setting.",
            wrong: "A withdraws the hint and drops V2. With a change, A also writes, which reverts B.",
            must: "V2 stays offered, and nothing is written until the user answers."
        ),
        "S-36": CatalogueText(
            setup: "B changes a setting and A shows Restart.",
            steps: "The file is deleted, then A quits and reopens. A changes a setting.",
            wrong: "The waiting version was held only in memory, so the hint is gone after the relaunch.",
            must: "A waiting version survives a relaunch (INV-9)."
        ),
        "S-37": CatalogueText(
            setup: "B Command-drags and changes \"Show on hover\". A, without touching the layout, changes it the other way and chooses Keep This Mac's Settings.",
            steps: "The file is deleted. A changes a non-layout setting. B quits and reopens.",
            wrong: "A's write over the missing file lists A's own layout (with holzBar's placements) as current, and B applies it over its own arrangement.",
            must: "B keeps its arrangement. A takes it in later, or its next drag asks."
        ),
        "S-38": CatalogueText(
            setup: "As S-37 step 1.",
            steps: "The file is deleted. A changes \"Show on hover\", then changes it back (two writes). B reopens and Command-drags.",
            wrong: "The first write marked A's layout as a copy. The second took the copy for \"no layout\" and listed A's layout as current. B applied it silently.",
            must: "B keeps its arrangement and takes A's setting. B's drag lists B's layout as current again."
        ),
        "S-39": CatalogueText(
            setup: "A and B on N; a variant with a third Mac.",
            steps: "B changes \"Show on hover\". Before A reads it the file is deleted. A changes a setting, then another. Variant: a third Mac applies A's file and changes a setting.",
            wrong: "A's second write hides that B's write is missing. B applied the version and lost its change.",
            must: "B asks, or the change is merged, however many writes follow."
        ),
        "S-40": CatalogueText(
            setup: "A, B and C on N. C restarted with A's arrangement before the deletion.",
            steps: "A Command-drags. Before B reads it, the file is deleted. B changes \"Show on hover\"; B's write lacks A's. C checks.",
            wrong: "C applied B's version silently and lost A's arrangement, which it already held.",
            must: "C keeps the arrangement after a relaunch."
        ),
        "S-41": CatalogueText(
            setup: "As S-38 steps 1 and 2.",
            steps: "B changes a setting; A restarts with it and keeps its own arrangement. The file is deleted, A changes a setting, B reopens.",
            wrong: "A's write over the missing file listed A's stale layout as current, and B applied it silently.",
            must: "B keeps its arrangement."
        ),
        "S-42": CatalogueText(
            setup: "A on N.",
            steps: "A changes a setting and writes; the file is copied aside. A Command-drags and writes again. The copy is put back. A quits and reopens, and changes \"Show on hover\".",
            wrong: "At launch A took in its own older version, which reverted its drag. The next write would have spread the stale layout.",
            must: "A keeps the drag, and its next write lists the dragged layout as current."
        ),
        "S-43": CatalogueText(
            setup: "A file in the folder becomes unusable: empty, damaged, a plist without the settings key, a symbolic link or a folder, over 1 MiB.",
            steps: "Another Mac reads it, changes a setting and writes.",
            wrong: "The file was mapped to \"unusable\" and written over at the next local change, and a waiting version was dropped.",
            must: "A file holzBar cannot interpret never counts as \"no other Mac wrote here\". No overwrite loses another Mac's change silently, and the user sees the state."
        ),
        "S-44": CatalogueText(
            setup: "A, on N, chooses an empty folder with Change…. Later B joins.",
            steps: "A changes the folder; B turns sync on in it.",
            wrong: "A fix for S-34 to S-41 that stalls the first write.",
            must: "A publishes its complete state, with its layout listed as current, without any question. B's join follows S-01 and S-07."
        ),
    ]
}

extension SimScenario {
    /// The file of `owner` is present in the folder (the Mac healed it, or wrote it under a new name).
    func expectFile(of owner: SimMacName) -> SimScenario {
        expect("\(owner) has a file in the folder") { world in
            guard let path = Catalogue.ownPath(world, owner) else { return "\(owner) has no device file" }
            if case .present? = world.replica(of: owner).entries[path] { return nil }
            return "\(owner) has no file at \(path)"
        }
    }
}

/// The G6 scenarios, one test each.
@Suite("CatalogueG6FileFaults")
struct CatalogueG6FileFaultsTests {
    @Test("A1 G6: the file goes missing, is restored or becomes unusable", arguments: CatalogueG6FileFaults.scenarios)
    func scenario(_ scenario: CatalogueScenario) async {
        await HeavyTestGate.run {
            Catalogue.check(scenario)
        }
    }
}
