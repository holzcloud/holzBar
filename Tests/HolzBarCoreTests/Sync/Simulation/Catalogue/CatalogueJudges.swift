//
//  CatalogueJudges.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The 16 scenarios the judges added to the catalogue (J-01 to J-16, section 5.7 of the analysis): the pause gap, version
/// skew, preference restores, dot reuse, corrupt own files, re-keys, collisions under one ID, clashing hotkeys, oversize
/// icons and simultaneous foundings. Each one runs the real engine in the simulator under the safety and layout oracles
/// and asserts its Must; a world that creates a collision or a hotkey on purpose leaves out the oracles that cannot judge
/// it, with a comment.
nonisolated enum CatalogueJudges {
    static let scenarios: [CatalogueScenario] = [
        j01, j02, j03, j04, j05, j06, j07, j08, j09, j10, j11, j12, j13, j14, j15, j16,
    ]

    private typealias D3 = CatalogueD3
    private typealias Tables = CatalogueExtraTables

    /// The sheet of a Mac shows `unit` with these two tokens.
    private static func asks(_ world: SimWorld, _ mac: SimMacName, _ unit: String, local: String?, folder: String?) -> String? {
        let shown = D3.shown(world, mac)
        return shown.contains { $0.unit == unit && $0.local == local && $0.folder == folder } ? nil : "\(mac)'s sheet shows \(shown)"
    }

    // MARK: J-01

    // J-01 · A synced setting is set back to its default during beta2, while the group has another value · class: added.
    static let j01 = CatalogueScenario(id: "J-01", title: "A setting set back during the beta2 pause is a present value: asked, never forced back", source: .judge, kind: .added) {
        let hover = Catalogue.hover
        let paused = Catalogue.scenario("J-01", macs: D3.running([.A, .B]))
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            .restartApp(.B)
            .settle()
            // The pause: A runs 0.0.7-beta2, which syncs nothing, and its user sets the setting back to the default
            // while B's user changes it for the group.
            .updateApp(.A, .beta2)
            .launch(.A)
            .edit(.B, hover, value: Catalogue.user(2, hover))
            .settle()
            .edit(.A, hover, value: Catalogue.user(5, hover))
            .updateApp(.A, .redesign)
            .launch(.A)
            .settle()
            .expectValue(.A, hover, Catalogue.user(5, hover))
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about the value it holds against the group's") { world in
                asks(world, .A, hover, local: "u5@\(hover)", folder: "u2@\(hover)")
            }
            .expect("the group's value still waits on A") { world in
                Catalogue.live(world, .A, hover).contains(Catalogue.user(2, hover)) ? nil : "A's replica holds \(Catalogue.live(world, .A, hover).map(\.canonical))"
            }
            .expectValue(.B, hover, Catalogue.user(2, hover))
            // Keep takes the value the user set; Use takes the group's. Neither is forced.
            .answer(.A, .use)
            .settle()
            .expectUser(.A, hover, 2)
            .expectUser(.B, hover, 2)
            .expectQuiet()
        return Catalogue.run(paused)
    }

    // MARK: J-02

    // J-02 · ⌘⇧H assigned to different actions on two Macs · class: added. The hotkeys are bare combinations that carry no
    // token, so the oracles that follow the tokens of a value are left out of this world.
    static let j02 = CatalogueScenario(id: "J-02", title: "One combination on two actions is a clash row, and no hotkey ends dead or in a Restart that never goes", source: .judge, kind: .added) {
        let table = Tables.table(hotkeyFamily: true)
        let combination = Tables.combination(4)
        let toggle = Tables.hotkeyToggle
        let search = Tables.hotkeySearch
        let holders: (SimWorld, SimMacName) -> [String] = { world, mac in
            [toggle, search].filter { Catalogue.value(world, mac, $0) == combination }
        }
        let scenario = Catalogue.scenario("J-02", macs: D3.running([.A, .B]))
            .brains { _, _ in Tables.hotkeyBrain(table: table) }
            .oracles(Tables.fileOracles)
            .offline(.B, seconds: 3_600)
            .edit(.A, toggle, value: combination)
            .edit(.B, search, value: combination)
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expect("a clash row on both Macs") { world in
                [SimMacName.A, .B].compactMap { mac in
                    Set(D3.shown(world, mac).map(\.unit)) == [toggle, search] ? nil : "\(mac)'s sheet shows \(D3.shown(world, mac).map(\.unit))"
                }.first
            }
            // A keeps the combination for its own action: the other action loses it on both Macs.
            .answer(.A, .keep)
            .settle()
            .expect("A holds the combination once") { world in
                holders(world, .A) == [toggle] ? nil : "A holds it for \(holders(world, .A))"
            }
            .expect("B is told to restart and has no sheet") { world in
                world.brains[.B]?.openPrompt == nil && world.brains[.B]?.hint != nil ? nil : "B shows \(world.brains[.B]?.hint ?? "no hint")"
            }
            .restartApp(.B)
            .settle()
            .expect("exactly one action holds the combination on both Macs, and nobody holds it twice") { world in
                holders(world, .A) == [toggle] && holders(world, .B) == [toggle] ? nil : "A: \(holders(world, .A)), B: \(holders(world, .B))"
            }
            .expectSilent()
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: J-03

    // J-03 · An N1 Mac and an N2 Mac (N2 has an extra appearance field) relaunch repeatedly · class: added.
    static let j03 = CatalogueScenario(id: "J-03", title: "Builds that store the appearance differently relaunch for ever with no dot, no hint and no stripped field", source: .judge, kind: .added) {
        let appearance = SimMacRedesign.appearanceUnit
        let descriptors = Tables.descriptors(appearance: true)
        let first = SyncUnitTable(version: 1, descriptors: descriptors)
        let skewed = SimMacRedesign.skew(descriptors: descriptors, extraAppearanceField: "extra")
        let v1 = SimValue.data(SimMacBeta2.userEncodedJSON(token: "u1@\(appearance)", extra: [:]))
        let v2 = SimValue.data(SimMacBeta2.userEncodedJSON(token: "u2@\(appearance)", extra: ["extra": "custom"]))
        func carriesField(_ world: SimWorld, _ mac: SimMacName) -> Bool {
            guard case .data(let bytes)? = Catalogue.value(world, mac, appearance), let text = String(data: bytes, encoding: .utf8) else { return false }
            return text.contains("\"extra\"")
        }
        func rounds(_ scenario: SimScenario, _ count: Int) -> SimScenario {
            (0..<count).reduce(scenario) { current, _ in current.restartApp(.A).restartApp(.B).settle() }
        }
        let started = Catalogue.scenario("J-03", macs: [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesignSkew, running: true)])
            .brains { version, _ in version == .redesignSkew ? skewed : SimMacRedesign(table: first) }
            .edit(.A, appearance, value: v1)
            .settle()
            .restartApp(.B)
            .settle()
            // The next launch of B's build fills the extra field, as its app does at every launch.
            .restartApp(.B)
            .settle()
            .expect("B's build filled the field") { world in carriesField(world, .B) ? nil : "B's appearance has no extra field" }
        let relaunched = rounds(started, 2)
            .checkpoint()
        let scenario = rounds(relaunched, 8)
            .expectNoWrite(.A)
            .expectNoWrite(.B)
            .expectPrompts(count: 0)
            .expectSilent()
            .expect("B's build never stripped or minted anything") { world in
                guard let own = Catalogue.state(world, .B)?.mac else { return "B has no state" }
                let minted = Catalogue.publishedEntries(world, .B, appearance).filter { $0.dot.mac == own }
                return carriesField(world, .B) && minted.isEmpty ? nil : "B carries the field: \(carriesField(world, .B)), B minted \(minted.count) entries"
            }
            .expectValue(.A, appearance, v1)
            // B's user changes the appearance with a field that A's build does not fill: A takes it and never strips it.
            .edit(.B, appearance, value: v2)
            .settle()
            .restartApp(.A)
            .settle()
            .expect("A holds B's value with the field") { world in
                carriesField(world, .A) && Catalogue.value(world, .A, appearance)?.tokens == ["u2@\(appearance)"] ? nil : "A holds \(Catalogue.value(world, .A, appearance)?.canonical ?? "nothing")"
            }
            .checkpoint()
        let again = rounds(scenario, 6)
            .expectNoWrite(.A)
            .expectNoWrite(.B)
            .expect("A still holds B's value with the field") { world in
                carriesField(world, .A) && Catalogue.value(world, .A, appearance)?.tokens == ["u2@\(appearance)"] ? nil : "A holds \(Catalogue.value(world, .A, appearance)?.canonical ?? "nothing")"
            }
            .expectQuiet()
        return Catalogue.run(again)
    }

    // MARK: J-04

    // J-04 · N, then beta2 with its load-time writers, then N · class: added.
    static let j04 = CatalogueScenario(id: "J-04", title: "Beta2's load-time writes are no change of the user's, and the user's own beta2 edits are captured", source: .judge, kind: .added) {
        let appearance = SimMacRedesign.appearanceUnit
        let table = Tables.table(appearance: true, normalizers: Tables.modelNormalizers)
        let stored = SimValue.data(SimMacBeta2.userEncodedJSON(token: "u1@\(appearance)", extra: ["futureField": "x"]))
        func minted(_ world: SimWorld, _ mac: SimMacName) -> Int {
            guard let own = Catalogue.state(world, mac)?.mac else { return -1 }
            return Catalogue.publishedEntries(world, mac, appearance).filter { $0.dot.mac == own }.count
        }
        let scenario = Catalogue.scenario("J-04", macs: D3.running([.A, .B]))
            .brains { version, _ -> any SimSyncBrain in
                if version == .beta2 { return SimMacBeta2() }
                return SimMacRedesign(table: table)
            }
            .edit(.A, appearance, value: stored)
            .settle()
            .expect("A published its appearance once") { world in minted(world, .A) == 1 ? nil : "A minted \(minted(world, .A)) entries" }
            .restartApp(.B)
            .settle()
            .updateApp(.A, .beta2)
            .launch(.A)
            .expect("beta2 rewrote the stored appearance") { world in
                Catalogue.value(world, .A, appearance) != stored ? nil : "the stored appearance is as it was"
            }
            // The user changes a setting while beta2 runs.
            .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
            .updateApp(.A, .redesign)
            .launch(.A)
            .settle()
            .expect("no dot came from beta2's writes") { world in minted(world, .A) == 1 ? nil : "A minted \(minted(world, .A)) entries for the appearance" }
            .expectPrompts(count: 0)
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 2)
            .expectUser(.A, Catalogue.hover, 2)
            .expect("B's appearance is as A first published it") { world in
                Catalogue.value(world, .B, appearance)?.tokens == ["u1@\(appearance)"] ? nil : "B holds \(Catalogue.value(world, .B, appearance)?.canonical ?? "nothing")"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: J-05

    // J-05 · Preferences restored two weeks back, Σ intact and trusted otherwise · class: added.
    static let j05 = CatalogueScenario(id: "J-05", title: "Preferences restored with the state intact are a join without a dot: asked, and a Keep is an explicit entry", source: .judge, kind: .added) {
        let hover = Catalogue.hover
        let scenario = Catalogue.scenario("J-05", macs: D3.running([.A, .B]))
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .settle()
            // The backup is of this moment (the Mac's last launch).
            .restartApp(.A)
            .settle()
            .edit(.A, hover, value: Catalogue.user(2, hover))
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .restorePrefs(.A)
            .launch(.A)
            .settle()
            .expectValue(.A, hover, Catalogue.user(1, hover))
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about the restored value") { world in
                asks(world, .A, hover, local: "u1@\(hover)", folder: "u2@\(hover)")
            }
            .expect("the restored value is not published as a new change") { world in
                let published = Catalogue.publishedEntries(world, .A, hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return published == [Catalogue.user(2, hover)] ? nil : "A's file holds \(published.map(\.canonical))"
            }
            // Keep: the user chose the restored value, which is an entry of the answer and nothing else.
            .answer(.A, .keep)
            .settle()
            .expect("the answer is the only entry that carries the restored value") { world in
                let published = Catalogue.publishedEntries(world, .A, hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return published == [Catalogue.user(1, hover)] ? nil : "A's file holds \(published.map(\.canonical))"
            }
            .restartApp(.B)
            .restartApp(.A)
            .settle()
            .expectUser(.B, hover, 1)
            .expectUser(.A, hover, 1)
            .expectUser(.A, Catalogue.rehide, 3)
            .expectUser(.B, Catalogue.rehide, 3)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: J-06

    // J-06 · Full home restore, clock set back below the old counters, folder unreadable, an edit, then the folder returns
    // · class: added.
    static let j06 = CatalogueScenario(id: "J-06", title: "A restore with a clock set back re-identifies at the reuse check, and the edit made meanwhile is never dropped", source: .judge, kind: .added) {
        let before = CatalogueBox<String?>(nil)
        // INV-S7, INV-F5 and INV-ID2 are left out of this world: a restore takes back the state a Mac held in memory,
        // which the oracle sees leave at the next launch, and the re-identification that follows is not a join to the
        // oracle (the reason plan 28-10 gave for S-11).
        let scenario = Catalogue.scenario("J-06", macs: D3.running([.A, .B]))
            .oracles(SimOracleSet.safety.without(["INV-F5", "INV-ID2", "INV-S7"]))
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            // The backup is of this moment; A goes on and B reads what it publishes.
            .restartApp(.A)
            .settle()
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restartApp(.B)
            .settle()
            .perform("note A's ID") { world in
                before.value = SimMacRedesignProbe.id(of: world, .A)
                return []
            }
            // The home folder goes back, the caches with it, and the clock is set three hours back.
            .restoreHome(.A, keepCaches: false)
            .clockStep(.A, milliseconds: -3 * 3_600_000)
            .provider(.unmount(mac: .A))
            .launch(.A)
            .edit(.A, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
            .advance(seconds: 30)
            // The folder returns; the simulated folder is read at a launch, so A's next launch is its first look at it.
            .provider(.mount(mac: .A))
            .restartApp(.A)
            .settle()
            .expect("the reuse check re-identified A") { world in
                let now = SimMacRedesignProbe.id(of: world, .A)
                return now != nil && now != before.value ? nil : "A is \(now ?? "-"), it was \(before.value ?? "-")"
            }
            .restartApp(.B)
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.spacing, 3)
            .expectUser(.B, Catalogue.spacing, 3)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.hover, 1)
        return Catalogue.run(scenario)
    }

    // MARK: J-07

    // J-07 · A join where one listed file stays dataless · class: added.
    static let j07 = CatalogueScenario(id: "J-07", title: "A join with a file that stays dataless commits nothing, Cancel writes nothing, and the commit follows the download", source: .judge, kind: .added) {
        // Downloads take minutes, so the file is dataless while the join waits.
        let policy = SimFaultPolicy(medianDelayMilliseconds: 240_000, coalesceProbability: 1, duplicateProbability: 0)
        func world(_ name: String) -> SimScenario {
            SimScenario(name, seed: 1, policy: policy)
                .macs([SimMacSpec(.A, .redesign, running: true), D3.joiner(.C)])
                .brains(Catalogue.brain)
                .oracles(.safety)
                .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 7_200)
                .evictFile(of: .A, on: .C)
                .turnOn(.C)
                .advance(seconds: 5)
                .expect("the join waits: nothing is committed and nothing is written") { world in
                    if world.state(of: .C).enabled { return "C turned sync on" }
                    if !Catalogue.writes(world, by: .C).isEmpty { return "C wrote a file" }
                    return Catalogue.lines(world, .C).contains(.joining(waitingFiles: 1)) ? nil : "C's lines are \(Catalogue.lines(world, .C))"
                }
        }
        let cancelled = world("J-07 Cancel")
            .turnOff(.C)
            .advance(seconds: 7_200)
            .expect("Cancel wrote nothing, then or later") { world in
                Catalogue.writes(world, by: .C).isEmpty && !world.state(of: .C).enabled ? nil : "C wrote \(Catalogue.writes(world, by: .C).count) files or is on"
            }
        let committed = world("J-07 download")
            .advance(seconds: 7_200)
            .expect("the commit follows the download") { world in
                world.state(of: .C).enabled ? nil : "C is not on, its lines are \(Catalogue.lines(world, .C))"
            }
            .restartApp(.C)
            .advance(seconds: 7_200)
            .expectUser(.C, Catalogue.hover, 1)
        return Catalogue.combine("J-07", [cancelled, committed].map(Catalogue.run))
    }

    // MARK: J-08

    // J-08 · The own file stays corrupt · class: added.
    static let j08 = CatalogueScenario(id: "J-08", title: "An own file that stays corrupt is never overwritten: the Mac publishes under a new ID", source: .judge, kind: .added) {
        let before = CatalogueBox<String?>(nil)
        let oldPath = CatalogueBox<String?>(nil)
        // INV-ID2 is left out for the reason plan 28-10 gave for S-11: the engine goes on under a new identity and marks the
        // units of the old one as pre-existing instead of opening a join, which the oracle does not read as joining again.
        let scenario = Catalogue.scenario("J-08", macs: D3.running([.A, .B]))
            .oracles(SimOracleSet.safety.without(["INV-ID2"]))
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .perform("note A's ID and file") { world in
                before.value = SimMacRedesignProbe.id(of: world, .A)
                oldPath.value = Catalogue.ownPath(world, .A)
                return []
            }
            .foreignFile(of: .A, .garbage)
            .settle()
            // The simulated folder is read at a launch and at a signal, not by a poll: the second look comes with a
            // relaunch, more than ten minutes after the first.
            .restartApp(.A)
            .settle()
            .expect("A took a new ID") { world in
                let now = SimMacRedesignProbe.id(of: world, .A)
                return now != nil && now != before.value ? nil : "A is \(now ?? "-")"
            }
            .expect("the corrupt file was never written over") { world in
                guard let path = oldPath.value else { return "no path" }
                if case .present(let data)? = world.replica(of: .B).entries[path] { return data == Data("garbage".utf8) ? nil : "the old file changed" }
                return "the old file is gone"
            }
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.hover, 1)
        return Catalogue.run(scenario)
    }

    // MARK: J-09

    // J-09 · An item-icon choice on a title-changing app re-keys `ns:Title` → `ns:#1` · class: added. The values are item
    // icons, which are bare choices of an item, so the world leaves out the oracles that follow the origin of a value.
    static let j09 = CatalogueScenario(id: "J-09", title: "An item whose key changes publishes no deletion of its old key, and the other Mac keeps its choice", source: .judge, kind: .added) {
        let title = Tables.iconByTitle
        let index = Tables.iconByIndex
        let table = Tables.table(itemIcons: true)
        let aliased: SimMacRedesign = {
            var brain = SimMacRedesign(table: table)
            brain.aliases = [title: index]
            return brain
        }()
        let ownedBy: (SimWorld, SimMacName, String) -> [SyncEntry] = { world, mac, unit in
            Catalogue.publishedEntries(world, mac, unit)
        }
        let scenario = Catalogue.scenario("J-09", macs: D3.running([.A, .B]))
            .brains { _, mac in mac == .A ? aliased : SimMacRedesign(table: table) }
            .oracles(Tables.fileOracles)
            .edit(.A, title, value: Catalogue.user(1, title))
            .settle()
            .restartApp(.B)
            .settle()
            .expectValue(.B, title, Catalogue.user(1, title))
            .rekeyItem(.A, from: title, to: index)
            .settle()
            .expect("A holds the choice under the new key only") { world in
                Catalogue.value(world, .A, title) == nil && Catalogue.value(world, .A, index) == Catalogue.user(1, title)
                    ? nil : "A holds \(Catalogue.value(world, .A, title)?.canonical ?? "nothing") and \(Catalogue.value(world, .A, index)?.canonical ?? "nothing")"
            }
            .expect("A published no deletion of the old key") { world in
                let entries = ownedBy(world, .A, title)
                return !entries.isEmpty && entries.allSatisfy({ $0.payload != .deleted }) ? nil : "A's file holds \(entries.map(\.payload))"
            }
            .restartApp(.B)
            .settle()
            .expectValue(.B, title, Catalogue.user(1, title))
            .expectSilent()
        return Catalogue.run(scenario)
    }

    // MARK: J-10

    // J-10 · Two installations collide under one ID on iCloud with per-device winners · class: added.
    // Both installations write the same file in the same second and mint the same counter under one ID; the provider keeps
    // each content as the winner on its own Mac. The oracles that cannot tell one dot with two payloads apart are left out.
    static let j10 = CatalogueScenario(id: "J-10", title: "Two installations under one ID with per-device winners: found on both sides, nothing lost", source: .judge, kind: .added) {
        let policy = SimFaultPolicy(
            medianDelayMilliseconds: 2_000, coalesceProbability: 1, conflictCopyProbability: 1, conflictStyles: [.perDeviceWinner]
        )
        let before = CatalogueBox<String?>(nil)
        let scenario = SimScenario("J-10", seed: 1, policy: policy)
            .macs(D3.running([.A, .B]) + [SimMacSpec(.C, .redesign, enabled: false, folder: nil, running: false)])
            .brains(Catalogue.brain)
            .oracles(SimOracleSet.safety.without(["INV-F5", "INV-ID1", "INV-ID2", "INV-ID3", "INV-S3", "INV-S7"]))
            .settle()
            .perform("note A's ID") { world in
                before.value = SimMacRedesignProbe.id(of: world, .A)
                return []
            }
            .duplicateInstallation(source: .A, target: .C)
            .launch(.C)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .edit(.C, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 3)
            .settle()
            .relaunchAll()
            .settle()
            .relaunchAll()
            .expect("the collision was found on both sides: each installation has an ID of its own now") { world in
                let a = SimMacRedesignProbe.id(of: world, .A)
                let c = SimMacRedesignProbe.id(of: world, .C)
                let both = a != nil && c != nil && a != c && a != before.value && c != before.value
                return both ? nil : "A is \(a ?? "-"), C is \(c ?? "-"), it was \(before.value ?? "-")"
            }
            .expect("nothing is lost: both settings are held by every Mac") { world in
                var missing: [String] = []
                for mac in [SimMacName.A, .B, .C] {
                    if Catalogue.value(world, mac, Catalogue.hover) != Catalogue.user(1, Catalogue.hover) { missing.append("\(mac) hover") }
                    if Catalogue.value(world, mac, Catalogue.rehide) != Catalogue.user(2, Catalogue.rehide) { missing.append("\(mac) rehide") }
                }
                return missing.isEmpty ? nil : "missing: \(missing)"
            }
        return Catalogue.run(scenario)
    }

    // MARK: J-11

    // J-11 · A new item appears on both Macs · class: added.
    static let j11 = CatalogueScenario(id: "J-11", title: "A new item on two Macs: no dot, no question, no hint, learned lists never merged, known applications unioned", source: .judge, kind: .added) {
        let specs = D3.running([.A, .B], generation: 27) + D3.running([.C], generation: 26)
        let known = "KnownApplications27"
        let tags = "KnownItemTags"
        func elements(_ world: SimWorld, _ mac: SimMacName, _ key: String) -> [SimValue] {
            if case .array(let list)? = world.defaults(of: mac)[key] { return list }
            return []
        }
        let scenario = Catalogue.scenario("J-11", macs: specs)
            .learn(.A, tags)
            .learn(.B, tags)
            .learn(.C, tags)
            .placeNewApp27(.A, bundle: "com.app.c")
            .placeNewApp27(.B, bundle: "com.app.d")
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            .expect("A and B know both applications") { world in
                let want: Set<SimValue> = [.string("com.app.c"), .string("com.app.d")]
                return [SimMacName.A, .B].allSatisfy { Set(elements(world, $0, known)) == want } ? nil
                    : "A knows \(elements(world, .A, known).map(\.canonical)), B knows \(elements(world, .B, known).map(\.canonical))"
            }
            .expect("the macOS 26 Mac knows none") { world in
                elements(world, .C, known).isEmpty ? nil : "C knows \(elements(world, .C, known).map(\.canonical))"
            }
            .expect("every learned list stays on its Mac") { world in
                let lists = [SimMacName.A, .B, .C].map { Set(elements(world, $0, tags).map(\.canonical)) }
                return lists.allSatisfy { $0.count == 1 } && Set(lists.flatMap { $0 }).count == 3 ? nil : "the lists are \(lists)"
            }
            .expect("each Mac places by itself: B has no placement of A's") { world in
                Catalogue.value(world, .B, "l27/com.app.c") == nil && Catalogue.value(world, .A, "l27/com.app.d") == nil
                    ? nil : "a placement travelled"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: J-12

    // J-12 · Three Macs change one setting differently · class: added.
    static let j12 = CatalogueScenario(id: "J-12", title: "Three values of one setting give a row with no default, and an answer without a choice is refused", source: .judge, kind: .added) {
        let hover = Catalogue.hover
        let key = SyncUnitKey.whole(hover)
        let environment = SyncEnvironment(
            table: Catalogue.table, generation: .g26, now: Date(timeIntervalSince1970: 1_790_000_000), unixSeconds: 1_790_000_000
        )
        let scenario = Catalogue.scenario("J-12", macs: D3.running([.A, .B, .C]))
            .offline(.B, seconds: 3_600)
            .offline(.C, seconds: 3_600)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .edit(.B, hover, value: Catalogue.user(2, hover))
            .edit(.C, hover, value: Catalogue.user(3, hover))
            .advance(seconds: 30)
            .online(.B)
            .online(.C)
            .settle()
            .expect("A's row lists three values, has no default, and an answer with no choice is refused") { world in
                guard var state = Catalogue.state(world, .A), let held = Catalogue.value(world, .A, hover), let local = SyncValue(sim: held) else {
                    return "A has no state"
                }
                let snapshot = SyncSnapshot(values: [key: local])
                state.session.snapshot = snapshot
                guard let question = SyncEngine.question(for: state, scope: .mine, environment: environment), let row = question.rows.first else {
                    return "A has no question"
                }
                guard row.style == .multi, row.folder.count == 3 else { return "the row is \(row.style) with \(row.folder.count) values" }
                var refused = state
                let none = SyncAnswerRequest(button: .use, choices: [:], question: question)
                if SyncEngine.writeAnswers(none, state: &refused, snapshot: snapshot, environment: environment) != nil {
                    return "an answer with no choice was taken"
                }
                var chosen = state
                let pick = SyncAnswerRequest(button: .useChosen, choices: [key: 1], question: question)
                return SyncEngine.writeAnswers(pick, state: &chosen, snapshot: snapshot, environment: environment) == nil ? "a choice was refused" : nil
            }
            // The user picks the third value: every Mac ends with it.
            .answer(.A, .pick([hover: .folder]))
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expect("the Macs agree") { world in
                let held = Set([SimMacName.A, .B, .C].compactMap { Catalogue.value(world, $0, hover)?.canonical })
                return held.count == 1 ? nil : "the Macs hold \(held.sorted())"
            }
        return Catalogue.run(scenario)
    }

    // MARK: J-13

    // J-13 · An oversize icon on A, then a small icon on B · class: added.
    static let j13 = CatalogueScenario(id: "J-13", title: "An oversize icon stays on its Mac with the note, and a small icon of another Mac never replaces it", source: .judge, kind: .added) {
        let icon = Catalogue.icon
        let small = Catalogue.big(2, icon, bytes: 1_000)
        let large = Catalogue.big(1, icon, bytes: 400 << 10)
        let scenario = Catalogue.scenario("J-13", macs: D3.running([.A, .B]))
            // B chooses a small icon first and A takes it; then A's user chooses an icon of 400 KB.
            .edit(.B, icon, value: small)
            .settle()
            .restartApp(.A)
            .settle()
            .expectValue(.A, icon, small)
            .edit(.A, icon, value: large)
            .settle()
            .expect("A shows the note") { world in
                Catalogue.lines(world, .A).contains(.oversizeIcon) ? nil : "A's lines are \(Catalogue.lines(world, .A))"
            }
            // B's small icon is the group's value and it waits on A, which never applies it over the local icon.
            .restartApp(.A)
            .settle()
            .restartApp(.B)
            .settle()
            .expectValue(.A, icon, large)
            .expectValue(.B, icon, small)
            .expectHint(.A, present: false)
            .expectPrompts(count: 0)
            .expect("A still shows the note") { world in
                Catalogue.lines(world, .A).contains(.oversizeIcon) ? nil : "A's lines are \(Catalogue.lines(world, .A))"
            }
        return Catalogue.run(scenario)
    }

    // MARK: J-14

    // J-14 · Two Macs found the group at the same moment · class: added.
    static let j14 = CatalogueScenario(id: "J-14", title: "Two foundings at one moment: equal values collapse and each differing unit is one question", source: .judge, kind: .added) {
        let hover = Catalogue.hover
        let rehide = Catalogue.rehide
        let equal = Catalogue.pre(.A)
        let specs = [
            D3.joiner(.A, defaults: [hover: Catalogue.pre(.A), rehide: equal]),
            D3.joiner(.B, defaults: [hover: Catalogue.pre(.B), rehide: equal]),
        ]
        // INV-F5 is left out of this world: the values at a founding are `pre` values, which no user change made, so the
        // simulator's ground truth takes every version of this world to have an empty past and so to be dominated, and
        // sees an unjustified reaction in the question that the other Mac's file rightly raises.
        let scenario = Catalogue.scenario("J-14", macs: specs)
            .oracles(SimOracleSet.safety.without(["INV-F5"]))
            .offline(.A, seconds: 600)
            .offline(.B, seconds: 600)
            .turnOn(.A)
            .turnOn(.B)
            .advance(seconds: 60)
            .online(.A)
            .online(.B)
            .settle()
            .expectPrompts(count: 1, mac: .A)
            .expectPrompts(count: 1, mac: .B)
            .expect("each Mac asks about the one setting that differs") { world in
                [SimMacName.A, .B].compactMap { mac in
                    Set(D3.shown(world, mac).map(\.unit)) == [hover] ? nil : "\(mac)'s sheet shows \(D3.shown(world, mac).map(\.unit))"
                }.first
            }
            .answer(.A, .use)
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expect("the Macs agree on both settings") { world in
                let a = [hover, rehide].map { Catalogue.value(world, .A, $0) }
                let b = [hover, rehide].map { Catalogue.value(world, .B, $0) }
                return a == b && a[1] == equal ? nil : "A holds \(a.map { $0?.canonical ?? "-" }), B holds \(b.map { $0?.canonical ?? "-" })"
            }
            .expect("B was asked once") { world in
                Catalogue.promptCount(world) <= 3 ? nil : "\(Catalogue.promptCount(world)) sheets opened"
            }
        return Catalogue.run(scenario)
    }

    // MARK: J-15

    // J-15 · A copied account on the same Mac · class: added.
    static let j15 = CatalogueScenario(id: "J-15", title: "A copied account gets a different uid-bound hash and an ID of its own, and both sync with a third Mac", source: .judge, kind: .added) {
        let specs = [
            SimMacSpec(.A, .redesign, running: true),
            SimMacSpec(.B, .redesign, enabled: false, folder: nil, running: false),
            SimMacSpec(.C, .redesign, running: true),
        ]
        let scenario = Catalogue.scenario("J-15", macs: specs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .copyAccount(from: .A, to: .B)
            .launch(.B)
            .settle()
            .expect("the hash that binds the ID to the account differs, and so do the IDs") { world in
                let hashes = [SimMacName.A, .B].map { world.defaults(of: $0)[SimMacRedesign.deviceHashKey] }
                let ids = [SimMacName.A, .B].map { SimMacRedesignProbe.id(of: world, $0) }
                return hashes[0] != nil && hashes[0] != hashes[1] && ids[0] != nil && ids[1] != nil && ids[0] != ids[1]
                    ? nil : "hashes \(hashes.map { $0?.canonical ?? "-" }), IDs \(ids.map { $0 ?? "-" })"
            }
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .edit(.C, Catalogue.spacing, value: Catalogue.user(3, Catalogue.spacing))
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.C, Catalogue.rehide, 2)
            .expectUser(.A, Catalogue.spacing, 3)
            .expectUser(.B, Catalogue.spacing, 3)
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: J-16

    // J-16 · A beta1 Mac rewrites Settings.plist 100 times · class: added.
    static let j16 = CatalogueScenario(id: "J-16", title: "A hundred beta1 rewrites: no hint and no question on a redesigned Mac, only the older-holzBar line", source: .judge, kind: .added) {
        let hover = Catalogue.hover
        var scenario = Catalogue.scenario(
            "J-16",
            macs: [
                SimMacSpec(.A, .redesign, generation: 26, running: true),
                SimMacSpec(.B, .redesign, generation: 27, running: true),
                SimMacSpec(.C, .beta1, generation: 26, running: true, defaults: [hover: Catalogue.pre(.C)]),
            ]
        )
        for round in 1...100 {
            scenario = scenario
                .edit(.C, hover, value: Catalogue.user(100 + round, hover))
                .advance(seconds: 6)
        }
        scenario = scenario
            .settle()
            .expect("the beta1 peer wrote the legacy file again and again") { world in
                Catalogue.writes(world, by: .C, path: SimMacBeta1.filePath).count >= 100 ? nil : "C wrote \(Catalogue.writes(world, by: .C, path: SimMacBeta1.filePath).count) times"
            }
            .expectOlderLine(.A, present: true)
            .expectOlderLine(.B, present: true)
            .expectBoundary(redesigned: [.A, .B])
            .expectNoLayoutQuestion()
            .expectKey(.C, Catalogue.sections, nil)
        return Catalogue.run(scenario)
    }
}

/// The judges' scenarios, one test each.
@Suite("CatalogueJudges")
struct CatalogueJudgesTests {
    @Test("Analysis section 5.7: the scenarios the judges added", arguments: CatalogueExtraTables.selected(CatalogueJudges.scenarios))
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
