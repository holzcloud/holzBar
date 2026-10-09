//
//  CatalogueA2Residual.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The scenarios of the A2 catalogue (SC-01 to SC-71) that no scenario of A1, D3 or the judges asserts: deleted and
/// imported hotkeys, learned applications of macOS 27, the generation scenarios SC-30 to SC-36 in their macOS 27 form
/// (the arrangement, the profiles and the known applications, with the macOS 26 Mac untouched), the newer and the
/// device-only file, lost and rolled-back writes, and the two random campaigns. `CatalogueExtraCoverageTests` maps every
/// other A2 scenario to the scenario that asserts it.
nonisolated enum CatalogueA2Residual {
    static let scenarios: [CatalogueScenario] = [
        sc08, sc16, sc17, sc24, sc30, sc31, sc32, sc33, sc34, sc35, sc36, sc46, sc47, sc64, sc65, sc70, sc71,
    ]

    private typealias D3 = CatalogueD3

    // MARK: SC-08

    // SC-08 · `ChangeFolder` to a folder holding another set → join on the new folder; Cancel keeps the old folder.
    static let sc08 = CatalogueScenario(id: "SC-08", title: "Change… to a folder with another group joins that group, and Cancel keeps the old folder", source: .a2, kind: .added) {
        let hover = Catalogue.hover
        // The folder `F2` is on A's disk already, as the provider keeps it, with D's file in it.
        let specs = [
            SimMacSpec(.A, .redesign, generation: 26, running: true, alsoOnDisk: ["F2"]),
            SimMacSpec(.B, .redesign, generation: 26, running: true),
            SimMacSpec(.D, .redesign, generation: 26, enabled: true, folder: "F2", running: true),
        ]
        let scenario = Catalogue.scenario("SC-08", macs: specs)
            .edit(.A, hover, value: Catalogue.user(1, hover))
            .edit(.D, hover, value: Catalogue.user(2, hover))
            .settle()
            .changeFolder(.A, folder: "F2")
            .settle()
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks about the two values of the other group") { world in
                D3.shown(world, .A).contains { $0.unit == hover && $0.local == "u1@\(hover)" && $0.folder == "u2@\(hover)" }
                    ? nil : "A's sheet shows \(D3.shown(world, .A))"
            }
            .answer(.A, .cancel)
            .settle()
            .expect("A is still in its own folder, with sync on") { world in
                let state = world.state(of: .A)
                return state.enabled && state.folderID == "F1" ? nil : "A is \(state.enabled ? "on" : "off") in \(state.folderID ?? "no folder")"
            }
            .expectUser(.A, hover, 1)
            // A still syncs with B.
            .edit(.B, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .expectHint(.A, present: true)
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.rehide, 3)
            .expectUser(.A, hover, 1)
        return Catalogue.run(scenario)
    }

    // MARK: SC-16 and SC-17

    // SC-16 · A deletes a hotkey → B removes it (fast-forward); B's other keys are untouched [INV-S5, INV-S4].
    static let sc16 = CatalogueScenario(id: "SC-16", title: "A deleted hotkey reaches the other Mac as an explicit deletion of that hotkey only", source: .a2, kind: .added) {
        let toggle = Catalogue.hotkey
        let show = "Hotkeys/show"
        let hide = "Hotkeys/hide"
        func holds(_ world: SimWorld, _ mac: SimMacName, _ unit: String) -> Bool { Catalogue.value(world, mac, unit) != nil }
        let scenario = Catalogue.scenario("SC-16", macs: D3.running([.A, .B]))
            .setHotkey(.A, action: "toggle", combo: 1)
            .setHotkey(.A, action: "show", combo: 2)
            .setHotkey(.B, action: "hide", combo: 3)
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expect("both Macs hold all three hotkeys") { world in
                [SimMacName.A, .B].allSatisfy { mac in [toggle, show, hide].allSatisfy { holds(world, mac, $0) } } ? nil : "a hotkey is missing"
            }
            .delete(.A, toggle)
            .settle()
            .expect("A published an explicit deletion of that hotkey and of no other") { world in
                let deleted = [toggle, show, hide].filter { unit in Catalogue.publishedEntries(world, .A, unit).contains { $0.payload == .deleted } }
                return deleted == [toggle] ? nil : "A deleted \(deleted)"
            }
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expect("B lost that hotkey and kept the others") { world in
                !holds(world, .B, toggle) && holds(world, .B, show) && holds(world, .B, hide) ? nil : "B holds toggle \(holds(world, .B, toggle)), show \(holds(world, .B, show)), hide \(holds(world, .B, hide))"
            }
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // SC-17 · A imports a file that lacks Hotkeys (remove-missing) → the deletion travels to B as a user deletion [INV-S5].
    static let sc17 = CatalogueScenario(id: "SC-17", title: "An Import that lacks the Hotkeys setting deletes exactly the hotkeys the importing Mac had", source: .a2, kind: .added) {
        let toggle = Catalogue.hotkey
        let show = "Hotkeys/show"
        let hide = "Hotkeys/hide"
        let scenario = Catalogue.scenario("SC-17", macs: D3.running([.A, .B]))
            .setHotkey(.A, action: "toggle", combo: 1)
            .setHotkey(.A, action: "show", combo: 2)
            .settle()
            .restartApp(.B)
            .settle()
            // B gives itself a hotkey that A has never seen, while A imports a file with no hotkeys at all.
            .offline(.B, seconds: 3_600)
            .setHotkey(.B, action: "hide", combo: 3)
            .importFile(.A, units: [Catalogue.hover])
            .advance(seconds: 30)
            .online(.B)
            .settle()
            .expect("A deleted exactly the hotkeys it had") { world in
                let deleted = [toggle, show, hide].filter { unit in Catalogue.publishedEntries(world, .A, unit).contains { $0.payload == .deleted } }
                return deleted == [toggle, show] ? nil : "A deleted \(deleted)"
            }
            .restartApp(.B)
            .restartApp(.A)
            .settle()
            .expect("B lost the two and kept its own") { world in
                Catalogue.value(world, .B, toggle) == nil && Catalogue.value(world, .B, show) == nil && Catalogue.value(world, .B, hide) != nil
                    ? nil : "B holds toggle \(Catalogue.value(world, .B, toggle) != nil), show \(Catalogue.value(world, .B, show) != nil), hide \(Catalogue.value(world, .B, hide) != nil)"
            }
            .expect("A took B's hotkey") { world in Catalogue.value(world, .A, hide) != nil ? nil : "A has no hide hotkey" }
            .expectPrompts(count: 0)
        return Catalogue.run(scenario)
    }

    // MARK: SC-24

    // SC-24 · A learns tag T and B learns U → both end with {T, U}; no prompt; at most rate-limited writes [INV-K1, INV-K2, INV-C2].
    // On macOS 27 the learned set that syncs is `KnownApplications27`.
    static let sc24 = CatalogueScenario(id: "SC-24", title: "Known applications of macOS 27 union silently, and every other learned key and flag stays local", source: .a2, kind: .added) {
        let known = "KnownApplications27"
        func elements(_ world: SimWorld, _ mac: SimMacName, _ key: String) -> [SimValue] {
            if case .array(let list)? = world.defaults(of: mac)[key] { return list }
            return []
        }
        let scenario = Catalogue.scenario("SC-24", macs: D3.running([.A, .B], generation: 27) + D3.running([.C], generation: 26))
            .placeNewApp27(.A, bundle: "com.app.c")
            .placeNewApp27(.B, bundle: "com.app.d")
            .learn(.A, "KnownItemTags")
            .learn(.B, "TitleChangingItemOwners")
            .setFlag(.B, "MacOS27LayoutSeeded")
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            .expect("A and B end with both applications, C with none") { world in
                let want: Set<SimValue> = [.string("com.app.c"), .string("com.app.d")]
                let ends = [SimMacName.A, .B].allSatisfy { Set(elements(world, $0, known)) == want } && elements(world, .C, known).isEmpty
                return ends ? nil : "A \(elements(world, .A, known).map(\.canonical)), B \(elements(world, .B, known).map(\.canonical)), C \(elements(world, .C, known).map(\.canonical))"
            }
            .expect("every other learned key and flag stays on its Mac") { world in
                let tagsOnlyOnA = elements(world, .A, "KnownItemTags").count == 1 && elements(world, .B, "KnownItemTags").isEmpty
                let ownersOnlyOnB = elements(world, .B, "TitleChangingItemOwners").count == 1 && elements(world, .A, "TitleChangingItemOwners").isEmpty
                let flagOnlyOnB = world.defaults(of: .B)["MacOS27LayoutSeeded"] != nil && world.defaults(of: .A)["MacOS27LayoutSeeded"] == nil
                return tagsOnlyOnA && ownersOnlyOnB && flagOnlyOnB ? nil : "a learned key or flag travelled"
            }
            .expect("the writes are few") { world in
                let writes = Catalogue.writes(world, by: .A).count + Catalogue.writes(world, by: .B).count
                return writes <= 12 ? nil : "A and B wrote \(writes) files"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: SC-30 to SC-36

    /// The own arrangement of the macOS 26 Mac and of the macOS 27 Mac in the scenarios of this group.
    private static let sections26 = Catalogue.sectionsDefaults(Catalogue.pre(.A))
    private static let layout27 = Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 1, token: Catalogue.pre(.B))])

    // SC-30 · A₂₆ and B₂₇ with equal settings → no prompt; each keeps its own layout [INV-L1].
    static let sc30 = CatalogueScenario(id: "SC-30", title: "A generation-26 and a generation-27 Mac with equal settings need no question and keep their arrangements", source: .a2, kind: .added) {
        let equal = Catalogue.pre(.B)
        let specs = [
            D3.joiner(.A, generation: 26, defaults: [Catalogue.hover: equal].merging(sections26) { first, _ in first }),
            SimMacSpec(.B, .redesign, generation: 27, running: true, defaults: [Catalogue.hover: equal].merging(layout27) { first, _ in first }),
        ]
        let scenario = Catalogue.scenario("SC-30", macs: specs)
            .settle()
            .saveProfile(.B, "Work")
            .settle()
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expectKey(.A, Catalogue.sections, sections26[Catalogue.sections])
            .expectKey(.B, "MacOS27Layout", layout27["MacOS27Layout"])
            .expect("the macOS 26 Mac holds neither the arrangement nor the profile of macOS 27") { world in
                world.defaults(of: .A)["MacOS27Layout"] == nil && world.defaults(of: .A)["LayoutProfiles"] == nil ? nil : "A holds a key of macOS 27"
            }
            .expectSilent()
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // SC-31 · A₂₆ edits `ItemSections` → B₂₇ gets no hint, prompt or restart for it; it may relay [INV-L1, INV-K1].
    static let sc31 = CatalogueScenario(id: "SC-31", title: "A drag on macOS 26 reaches no hint, no question and no restart on a macOS 27 Mac", source: .a2, kind: .added) {
        let scenario = Catalogue.scenario("SC-31", macs: D3.running([.A], generation: 26) + D3.running([.B], generation: 27))
            .moveApp27(.B, bundle: Catalogue.appA, section: 1)
            .settle()
            .checkpoint()
            .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
            .advance(seconds: 30)
            .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(2, Catalogue.sectionsEntry))
            .settle()
            .restartApp(.A)
            .settle()
            .expectHint(.B, present: false)
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectNoWrite(.A)
            .expect("A keeps its drag, B its arrangement") { world in
                world.defaults(of: .A)[Catalogue.sections] == .dictionary(["Visible": Catalogue.user(2, Catalogue.sectionsEntry)])
                    && Catalogue.value(world, .B, Catalogue.layoutA) != nil ? nil : "an arrangement changed"
            }
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // SC-32 · B₂₇ edits `MacOS27Layout`; C₂₇ receives it; A₂₆ writes many times → A never reverts or removes B's g27 intent
    // [INV-L3, INV-L2]; the relayed profiles and known applications survive too.
    static let sc32 = CatalogueScenario(id: "SC-32", title: "A generation-26 Mac that writes many times never reverts or removes a generation-27 Mac's entries", source: .a2, kind: .added) {
        let profile = "prof/Work"
        let known = "KnownApplications27"
        let layout = CatalogueBox<SimValue?>(nil)
        let scenario = Catalogue.scenario("SC-32", macs: D3.running([.A], generation: 26) + D3.running([.B, .C], generation: 27))
            .moveApp27(.B, bundle: Catalogue.appA, section: 1)
            .placeNewApp27(.B, bundle: "com.app.c")
            .saveProfile(.B, "Work")
            .settle()
            .restartApp(.C)
            .settle()
            .perform("note B's arrangement") { world in
                layout.value = Catalogue.value(world, .B, Catalogue.layoutA)
                return layout.value == nil ? ["B has no arrangement"] : []
            }
            .expect("C took the arrangement, the profile and the known application") { world in
                Catalogue.value(world, .C, Catalogue.layoutA) == layout.value && Catalogue.value(world, .C, profile) != nil
                    && world.defaults(of: .C)[known] != nil ? nil : "C is missing one of them"
            }
        // A writes many times, each time a hotkey it has not had before.
        var writing = scenario
        for round in 1...8 {
            writing = writing
                .setHotkey(.A, action: "key\(round)", combo: round)
                .advance(seconds: 10)
            if round.isMultiple(of: 4) { writing = writing.restartApp(.A).settle() }
        }
        let final = writing
            .settle()
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expect("B and C still hold the arrangement, the profile and the known application") { world in
                [SimMacName.B, .C].allSatisfy {
                    Catalogue.value(world, $0, Catalogue.layoutA) == layout.value && Catalogue.value(world, $0, profile) != nil && world.defaults(of: $0)[known] != nil
                } ? nil : "a generation-27 Mac lost an entry"
            }
            .expect("A relays them in its file and never applies them") { world in
                let relays = !Catalogue.publishedEntries(world, .A, Catalogue.layoutA).isEmpty && !Catalogue.publishedEntries(world, .A, profile).isEmpty
                let applied = Catalogue.value(world, .A, Catalogue.layoutA) != nil || world.defaults(of: .A)["MacOS27Layout"] != nil
                return relays && !applied ? nil : "A relays \(relays), applied \(applied)"
            }
            .expectNoLayoutQuestion()
        return Catalogue.run(final)
    }

    // SC-33 · `UpgradeOS(A)` while B₂₇ holds a user layout → A seeds automatically, then takes in B's g27 layout silently
    // [INV-L6, INV-A1]. The same outcome as SC-04, which A2 states for a fresh Mac of the same generation.
    static let sc33 = CatalogueScenario(id: "SC-33", title: "An OS upgrade seeds, and then takes in the group's arrangement silently", source: .a2, kind: .added) {
        let scenario = Catalogue.scenario("SC-33", macs: D3.running([.A], generation: 26) + D3.running([.B], generation: 27))
            .moveApp27(.B, bundle: Catalogue.appA, section: 2)
            .settle()
            .upgradeOS(.A)
            .launch(.A)
            .seed27(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .restartApp(.A)
            .settle()
            .expect("A holds B's arrangement for the application B moved") { world in
                Catalogue.value(world, .A, Catalogue.layoutA) == Catalogue.value(world, .B, Catalogue.layoutA) && Catalogue.value(world, .A, Catalogue.layoutA) != nil
                    ? nil : "A holds \(Catalogue.value(world, .A, Catalogue.layoutA)?.canonical ?? "nothing")"
            }
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectSilent()
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // SC-34 · F-60: a g27 Mac reads a file written only by a g26 Mac → `MacOS27Layout`, `MacOS27LayoutSeeded` and
    // `KnownApplications27` are kept [INV-S4].
    static let sc34 = CatalogueScenario(id: "SC-34", title: "A macOS 27 Mac that reads the file of a macOS 26 Mac alone keeps its layout, its flag and its known applications", source: .a2, kind: .added) {
        let seeded = layout27.merging(["MacOS27LayoutSeeded": .bool(true), "KnownApplications27": .array([.string(Catalogue.appA)])]) { first, _ in first }
        let specs = D3.running([.A], generation: 26) + [D3.joiner(.B, generation: 27, defaults: seeded)]
        let scenario = Catalogue.scenario("SC-34", macs: specs)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .turnOn(.B)
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectKey(.B, "MacOS27Layout", seeded["MacOS27Layout"])
            .expectKey(.B, "MacOS27LayoutSeeded", .bool(true))
            .expectKey(.B, "KnownApplications27", seeded["KnownApplications27"])
            .expectPrompts(count: 0)
            // A writes again and B reads it again: nothing of B's goes.
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectKey(.B, "MacOS27Layout", seeded["MacOS27Layout"])
            .expectKey(.B, "KnownApplications27", seeded["KnownApplications27"])
        return Catalogue.run(scenario)
    }

    // SC-35 · A profile saved on 26 is applied on 27 → no empty layout and no deletions published (F-03) [INV-L6, R-FUN-9].
    // A profile saved on macOS 26 has no part for macOS 27, so applying it on macOS 27 changes no application.
    static let sc35 = CatalogueScenario(id: "SC-35", title: "A profile saved on macOS 26 and applied on macOS 27 changes nothing and publishes no deletion", source: .a2, kind: .added) {
        let profileOnly26 = ["LayoutProfiles": SimValue.dictionary([
            "Old": .dictionary(["name": .string("Old"), "sections27": .dictionary([:]), "token": Catalogue.pre(.B)]),
        ])]
        let specs = D3.running([.A], generation: 26) + [SimMacSpec(.B, .redesign, generation: 27, running: true, defaults: layout27.merging(profileOnly26) { first, _ in first })]
        let scenario = Catalogue.scenario("SC-35", macs: specs)
            .settle()
            .applyProfile(.B, "Old")
            .settle()
            .restartApp(.B)
            .settle()
            .expectKey(.B, "MacOS27Layout", layout27["MacOS27Layout"])
            .expect("B published no deletion at all") { world in
                guard let path = Catalogue.ownPath(world, .B), let write = Catalogue.writes(world, by: .B, path: path).last,
                      let deleted = (world.brains[.B] as? SimMacRedesign)?.deletedUnits(inFile: path, data: write.data)
                else { return "B has no file" }
                return deleted.isEmpty ? nil : "B deleted \(deleted.sorted())"
            }
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectHint(.A, present: false)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // SC-36 · Round 4 and 5 blockers: an old own version or a not-newer version carries a stale g26 layout and reaches A₂₇
    // → A₂₇ never re-publishes it as current; B₂₆ never applies it silently [INV-L4, INV-S3, INV-S2].
    static let sc36 = CatalogueScenario(id: "SC-36", title: "An older version that relays a stale layout never makes a macOS 27 Mac publish it as current, and a macOS 26 Mac applies nothing", source: .a2, kind: .added) {
        let box = CatalogueBox(-1)
        let latest = CatalogueBox<SimValue?>(nil)
        let scenario = Catalogue.scenario("SC-36", macs: D3.running([.A, .D], generation: 27) + D3.running([.C], generation: 26))
            .moveApp27(.D, bundle: Catalogue.appA, section: 1)
            .settle()
            // C's file relays the first layout; it is the version a sync app keeps or brings back.
            .edit(.C, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .markFile(of: .C, in: box)
            .moveApp27(.D, bundle: Catalogue.appA, section: 2)
            .settle()
            .restartApp(.A)
            .settle()
            .perform("note the newer layout") { world in
                latest.value = Catalogue.value(world, .D, Catalogue.layoutA)
                return []
            }
            .restoreFile(of: .C, to: box)
            .settle()
            .restartApp(.A)
            .settle()
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restartApp(.D)
            .restartApp(.C)
            .settle()
            .expect("A lists the newer layout and never the stale one") { world in
                let listed = Catalogue.publishedEntries(world, .A, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return listed == [latest.value].compactMap { $0 } ? nil : "A's file lists \(listed.map(\.canonical))"
            }
            .expect("A and D hold the newer layout") { world in
                [SimMacName.A, .D].allSatisfy { Catalogue.value(world, $0, Catalogue.layoutA) == latest.value } ? nil : "a Mac holds another layout"
            }
            .expect("C applies no layout and keeps its own drag") { world in
                world.defaults(of: .C)["MacOS27Layout"] == nil && Catalogue.value(world, .C, Catalogue.layoutA) == nil ? nil : "C holds a layout of macOS 27"
            }
            .expectNoLayoutQuestion()
            .expectUser(.C, Catalogue.rehide, 2)
        return Catalogue.run(scenario)
    }

    // MARK: SC-46 and SC-47

    /// A device file of another Mac, written by a build with a newer major format.
    private static func newerFormatFile(index: Int) -> (path: String, data: Data) {
        let mac = SyncMacID(UUID(uuidString: String(format: "%08X-0000-4000-8000-000000000000", 0xFFFF0000 + index)) ?? UUID())
        let contents = SyncDeviceFile.Contents(
            format: SyncDeviceFile.currentFormat + 1, unitTable: 9, mac: mac, installation: "future",
            written: Date(timeIntervalSince1970: 1_790_000_000), replica: .empty
        )
        return ("\(SimFolderIO.directory)/\(mac.rawValue).plist", (try? SyncDeviceFile.encode(contents)) ?? Data())
    }

    // SC-46 · An N+ file is present → A does not rewrite or prune it, and shows "update holzBar" [INV-B8].
    static let sc46 = CatalogueScenario(id: "SC-46", title: "A file of a newer format is never rewritten or pruned, and the status line says to update", source: .a2, kind: .added) {
        let planted = newerFormatFile(index: 1)
        let scenario = Catalogue.scenario("SC-46", macs: D3.running([.A, .B]))
            .provider(.plant(path: planted.path, data: planted.data))
            .settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.A)
            .restartApp(.B)
            .settle()
            .expect("both Macs show the line for a newer build") { world in
                [SimMacName.A, .B].allSatisfy { Catalogue.lines(world, $0).contains(.newerFormat) } ? nil : "A: \(Catalogue.lines(world, .A)), B: \(Catalogue.lines(world, .B))"
            }
            .expect("the file is as the newer build wrote it, and nobody wrote to its path") { world in
                guard case .present(let data)? = world.replica(of: .A).entries[planted.path], data == planted.data else { return "the file changed or is gone" }
                let written = [SimMacName.A, .B].flatMap { Catalogue.writes(world, by: $0, path: planted.path) }
                return written.isEmpty ? nil : "a Mac wrote \(planted.path)"
            }
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 0)
        return Catalogue.run(scenario)
    }

    // SC-47 · An L0-style file with only `device` → lineage-free; N never writes `device` [INV-B9, INV-PR2].
    static let sc47 = CatalogueScenario(id: "SC-47", title: "A legacy file with only a device field gives no lineage, and the redesigned build never writes a device field", source: .a2, kind: .added) {
        let hover = Catalogue.hover
        let legacy: [String: Any] = [
            "modified": Date(timeIntervalSince1970: 1_789_999_000),
            "device": "Studio",
            "settings": [hover: Catalogue.pre(.C).propertyList],
        ]
        let bytes = (try? PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0)) ?? Data()
        let scenario = Catalogue.scenario("SC-47", macs: [D3.joiner(.A, defaults: [hover: Catalogue.pre(.A)])])
            .provider(.plant(path: SimFolderIO.legacyPath, data: bytes))
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 1, mac: .A)
            .expect("A asks once, about the setting that differs") { world in
                Set(D3.shown(world, .A).map(\.unit)) == [hover] ? nil : "A's sheet shows \(D3.shown(world, .A).map(\.unit))"
            }
            .answer(.A, .keep)
            .settle()
            .edit(.A, Catalogue.rehide, value: Catalogue.user(1, Catalogue.rehide))
            .settle()
            .restartApp(.A)
            .settle()
            .expect("no file A wrote carries a device field, and A wrote the legacy file never") { world in
                for write in Catalogue.writes(world, by: .A) {
                    if write.path == SimFolderIO.legacyPath { return "A wrote the legacy file" }
                    guard let object = try? PropertyListSerialization.propertyList(from: write.data, options: [], format: nil), let root = object as? [String: Any] else {
                        return "\(write.path) is no property list"
                    }
                    if root["device"] != nil || root["deviceID"] != nil { return "\(write.path) carries a device field" }
                }
                return nil
            }
            .expect("the legacy file is as it was") { world in
                Catalogue.legacyBytes(world, as: .A) == bytes ? nil : "the legacy file changed"
            }
        return Catalogue.run(scenario)
    }

    // MARK: SC-64 and SC-65

    // SC-64 · SMB LWW: a write is lost → its writer sees that its publication is missing and re-publishes honestly [R-LIN-4,
    // INV-S1g]. The provider keeps the last writer's content, sends no folder signal and delays a little.
    static let sc64 = CatalogueScenario(id: "SC-64", title: "On a last-writer-wins share a lost write is noticed and published again, with no question where nothing is concurrent", source: .a2, kind: .added) {
        let policy = SimFaultPolicy(medianDelayMilliseconds: 500, conflictCopyProbability: 0, conflictStyles: [], signalsFolderChanges: false)
        let before = CatalogueBox(-1)
        let scenario = SimScenario("SC-64", seed: 1, policy: policy)
            .macs(D3.running([.A, .B]))
            .brains(Catalogue.brain)
            .oracles(.safety)
            .advance(seconds: 60)
            .edit(.B, Catalogue.spacing, value: Catalogue.user(4, Catalogue.spacing))
            .advance(seconds: 60)
            .markFile(of: .B, in: before)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .advance(seconds: 60)
            // The share takes B's last write back.
            .restoreFile(of: .B, to: before)
            .advance(seconds: 60)
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 60)
            .restartApp(.B)
            .advance(seconds: 600)
            .restartApp(.A)
            .advance(seconds: 600)
            .restartApp(.B)
            .advance(seconds: 600)
            .expect("B published its change again") { world in
                let values = Catalogue.publishedEntries(world, .B, Catalogue.rehide).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return values.contains(Catalogue.user(2, Catalogue.rehide)) ? nil : "B's file holds \(values.map(\.canonical)) for the setting"
            }
            .expectUser(.A, Catalogue.rehide, 2)
            .expectUser(.B, Catalogue.hover, 1)
            .expectPrompts(count: 0)
        return Catalogue.run(scenario)
    }

    // SC-65 · Syncthing rolls A's replica back to an old state of A's own file → A recognises it as its own older write and
    // re-publishes; no prompt [INV-ID4, R-LIN-4].
    static let sc65 = CatalogueScenario(id: "SC-65", title: "A rollback of the own file to an older own state is recognised, published again and never asked about", source: .a2, kind: .added) {
        let mark = CatalogueBox(-1)
        let scenario = Catalogue.scenario("SC-65", macs: D3.running([.A, .B]))
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .markFile(of: .A, in: mark)
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .restoreFile(of: .A, to: mark)
            .settle()
            .restartApp(.A)
            .settle()
            .expectPrompts(count: 0)
            .expect("A's file carries both settings again") { world in
                let hover = Catalogue.publishedEntries(world, .A, Catalogue.hover).compactMap(\.value).compactMap { SimValue(sync: $0) }
                let rehide = Catalogue.publishedEntries(world, .A, Catalogue.rehide).compactMap(\.value).compactMap { SimValue(sync: $0) }
                return hover == [Catalogue.user(1, Catalogue.hover)] && rehide == [Catalogue.user(2, Catalogue.rehide)] ? nil
                    : "A's file holds \(hover.map(\.canonical)) and \(rehide.map(\.canonical))"
            }
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expectUser(.B, Catalogue.rehide, 2)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(scenario)
    }

    // MARK: SC-70 and SC-71

    /// Two macOS 27 Macs and one macOS 26 Mac, all running with sync on.
    private static let campaignMacs = [
        SimMacSpec(.A, .redesign, generation: 27, running: true),
        SimMacSpec(.B, .redesign, generation: 27, running: true),
        SimMacSpec(.C, .redesign, generation: 26, running: true),
    ]

    /// The fixed seeds of the campaign of paired runs (SC-71).
    private static let campaignSeeds: [UInt64] = [11, 12, 13, 14, 15, 16]

    /// The seeds of the campaign that drains: the ones that found the faults of plan 28-12, with the ideal provider and with iCloud.
    private static let drainSeeds: [UInt64] = [11, 14, 15]

    /// Every Mac of a campaign runs the real engine on the table of the settings it syncs, which takes every value.
    private static func campaignBrain(_ version: SimMacVersion, _ mac: SimMacName) -> any SimSyncBrain {
        SimMacRedesign(table: Catalogue.laxTable)
    }

    /// The random events of one seed. The icon events are left out: the catalogue's table has no item icons.
    private static func campaignEvents(seed: UInt64, preset: SimProviderPreset?, steps: Int, quiet: Bool = false) -> [SimEvent] {
        var config = SimGenerator.Config(macs: campaignMacs, preset: preset, steps: steps)
        config.units = [Catalogue.hover, Catalogue.shelf, Catalogue.rehide, Catalogue.menus, Catalogue.hotkey]
        config.identityEvents = false
        if quiet {
            config.automaticEvents = false
            config.providerEvents = false
            config.clockEvents = false
        }
        // Two kinds of event are left out. The icon events: the catalogue's table has no item icons. And the automatic
        // writes of the arrangement and of the settings themselves: holzBar never changes a synced setting by itself,
        // and an automatic entry of the arrangement is no dot by decision D-04, so a Mac that joins later does not have
        // it, which the comparison of a fresh Mac (INV-C6) would count as a difference. SC-24 and SC-33 hold the
        // automatic stores that do exist.
        return SimGenerator.events(seed: seed, config).filter { event in
            switch event {
            case .oversizeIcon, .chooseItemIcon, .autoPlace, .seed27, .placeNewApp27: false
            default: true
            }
        }
    }

    // SC-70 · Three Macs (two g27, one g26), 200 random steps, then `Q(T0)` and a drain → INV-C1, INV-C2, INV-C3, INV-C5 and
    // INV-C6 hold.
    static let sc70 = CatalogueScenario(id: "SC-70", title: "Two hundred random steps on three Macs, then a drain: agreement, quiescence, bounded questions, progress and a fresh Mac's join", source: .a2, kind: .added) {
        var failures: [String] = []
        var last: SimWorld?
        for seed in drainSeeds {
            for preset in [nil, SimProviderPreset.iCloud] {
                let events = campaignEvents(seed: seed, preset: preset, steps: 200)
                let world = SimWorld(seed: seed, macs: campaignMacs, preset: preset, brainFactory: campaignBrain, oracles: .none)
                world.run(events)
                // The people answer one after the other. Two Macs that both press Use for one conflict at the same moment
                // take each other's value and are asked once more (D3-S04), and a drain that answers every open sheet
                // before anything is delivered would have them do that for as long as its answers repeat.
                var drain = SimDrainConfig()
                drain.answerOneAtATime = true
                let facts = SimDrain.run(world, config: drain)
                let label = "seed \(seed) \(preset?.rawValue ?? "ideal")"
                if !facts.disagreements.isEmpty { failures.append("\(label): the Macs disagree on \(facts.disagreements.prefix(3))") }
                if !facts.quiescent { failures.append("\(label): the drain never went quiet (\(facts.finalRoundWrites) writes in the last round)") }
                // A provider that delivers stale versions and keeps unresolved copies can make a Mac ask once more after an
                // answer whose conflict it has already seen settled elsewhere: each Mac may ask one more time then.
                let bound = facts.promptBound + (preset == nil ? 0 : campaignMacs.count)
                if facts.promptsAfterT0 > bound { failures.append("\(label): \(facts.promptsAfterT0) questions after T0, the bound is \(bound)") }
                if !facts.unreached.isEmpty { failures.append("\(label): \(facts.unreached.prefix(3)) never reached another Mac") }
                if !facts.freshMismatches.isEmpty { failures.append("\(label): a fresh Mac differs at \(facts.freshMismatches.prefix(3))") }
                last = world
            }
        }
        guard let last else { return SimScenarioResult(name: "SC-70", failures: ["no campaign ran"], world: SimWorld(seed: 1, macs: [])) }
        return SimScenarioResult(name: "SC-70", failures: failures, world: last)
    }

    // SC-71 · INV-A1 metamorphic pair of SC-70 (with and without automatic events) and INV-F9 metamorphic pair (random
    // clocks).
    static let sc71 = CatalogueScenario(id: "SC-71", title: "The paired runs, with and without automatic events and with random clocks, decide the same", source: .a2, kind: .added) {
        var failures: [String] = []
        var last: SimWorld?
        for seed in campaignSeeds {
            let setup = SimMetaSetup(seed: seed, preset: nil, macs: campaignMacs, brainFactory: campaignBrain)
            let events = campaignEvents(seed: seed, preset: nil, steps: 80, quiet: true)
            failures += SimMetamorphic.automaticEventsInvisible(setup, events, insertionSeed: seed).map { "seed \(seed): \($0.id) \($0.description)" }
            failures += SimMetamorphic.clockIndependence(setup, events, clockSeed: seed).map { "seed \(seed): \($0.id) \($0.description)" }
            last = SimWorld(seed: seed, macs: campaignMacs, brainFactory: campaignBrain, oracles: .none)
        }
        guard let last else { return SimScenarioResult(name: "SC-71", failures: ["no pair ran"], world: SimWorld(seed: 1, macs: [])) }
        return SimScenarioResult(name: "SC-71", failures: failures, world: last)
    }
}

/// The A2 scenarios that nothing else asserts, one test each.
@Suite("CatalogueA2Residual")
struct CatalogueA2ResidualTests {
    @Test("A2 section 7: the scenarios no earlier catalogue file asserts", arguments: CatalogueExtraTables.selected(CatalogueA2Residual.scenarios))
    func scenario(_ scenario: CatalogueScenario) async {
        await HeavyTestGate.run {
            Catalogue.check(scenario)
        }
    }
}
