//
//  CatalogueG3Generations.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G3 of the A1 regression catalogue (S-13 to S-19): two macOS versions. The arrangement of macOS 26 (`ItemSections`)
/// is local to each Mac; the arrangement of macOS 27 (`l27/*`) syncs between generation-27 Macs and passes through a
/// generation-26 Mac untouched (decisions D-04 and D-11). The SCOPE scenarios (S-15 to S-17) run on generation-26 Macs
/// with the arrangement keys asserted untouched and unprompted, and on generation-27 Macs in their arrangement form;
/// the BOUNDARY scenarios (S-18, S-19) run with a real 0.0.7-beta1 peer.
nonisolated enum CatalogueG3Generations {
    static let scenarios: [CatalogueScenario] = [s13, s14] + s15 + s16 + s17 + [s18, s19]

    // MARK: Building blocks

    /// One arrangement step of a form. A generation-27 Mac moves an application in the Layout pane; a generation-26 Mac
    /// drags an item, which changes `ItemSections`, a key that never syncs. `k` names the drag.
    static func arrange(_ scenario: SimScenario, _ mac: SimMacName, generation: Int, section: Int, k: Int) -> SimScenario {
        generation == 27
            ? scenario.moveApp27(mac, bundle: Catalogue.appA, section: section)
            : scenario.edit(mac, Catalogue.sectionsEntry, value: Catalogue.user(k, Catalogue.sectionsEntry))
    }

    /// The Macs of a form: running, in `F1`, all of one generation.
    static func specs(_ names: [SimMacName], generation: Int) -> [SimMacSpec] {
        names.map { SimMacSpec($0, .redesign, generation: generation, running: true) }
    }

    /// The assertions every form of S-15 to S-17 shares: no question about an arrangement, no settings reverted, and in
    /// the generation-26 form no Mac's `ItemSections` touched by sync (each holds its own last drag).
    static func common(_ scenario: SimScenario, generation: Int, drags: [SimMacName: Int]) -> SimScenario {
        var checked = scenario.expectNoLayoutQuestion()
        if generation == 26 {
            for (mac, k) in drags.sorted(by: { $0.key < $1.key }) {
                checked = checked.expect("\(mac) keeps its own arrangement") { world in
                    let held = world.defaults(of: mac)[Catalogue.sections]
                    let expected = SimValue.dictionary(["Visible": Catalogue.user(k, Catalogue.sectionsEntry)])
                    return held == expected ? nil : "\(mac) holds \(held?.canonical ?? "nothing") at \(Catalogue.sections)"
                }
            }
        }
        return checked
    }

    // MARK: S-13

    // S-13 · Applying a file of the other macOS version · A1 G3 · class: pass · source: F-60 (RC-4).
    static let s13 = CatalogueScenario(id: "S-13", title: "Applying a file of the other macOS version removes nothing", source: .a1, kind: .pass) {
        let seeded = Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 1, token: Catalogue.pre(.B))])
            .merging(["MacOS27LayoutSeeded": .bool(true), "KnownApplications27": .array([.string(Catalogue.appA)])]) { first, _ in first }
        let sections = Catalogue.sectionsDefaults(Catalogue.pre(.A))
        let specs = [
            SimMacSpec(.A, .redesign, generation: 26, running: true, defaults: sections),
            SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, defaults: seeded, syncedFolder: "F1"),
        ]
        func untouched(_ scenario: SimScenario) -> SimScenario {
            seeded.keys.sorted().reduce(scenario) { $0.expectKey(.B, $1, seeded[$1]) }
                .expectKey(.A, Catalogue.sections, sections[Catalogue.sections])
        }
        // A, on macOS 26, writes; B, on macOS 27, applies it and keeps its three keys.
        let toward27 = untouched(
            Catalogue.scenario("S-13 macOS 26 to 27", macs: specs)
                .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
                .turnOn(.B)
                .settle()
                .restartApp(.B)
                .settle()
                .expectUser(.B, Catalogue.hover, 1)
        )
        // B writes and A applies it: A keeps `ItemSections`.
        let toward26 = untouched(
            toward27
                .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .settle()
                .expectHint(.A, present: true)
                .restartApp(.A)
                .settle()
                .expectUser(.A, Catalogue.rehide, 2)
        )
        .expectPrompts(count: 0)
        .expectQuiet()
        return Catalogue.run(toward26)
    }

    // MARK: S-14

    // S-14 · macOS 26 and 27 with equal settings · A1 G3 · class: pass · source: SA-05, step G (must not ask).
    static let s14 = CatalogueScenario(id: "S-14", title: "macOS 26 and 27 with equal settings never ask about an arrangement", source: .a1, kind: .pass) {
        let equal = Catalogue.pre(.B)
        let layout = Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 1, token: Catalogue.pre(.B))])
        let specs = [
            SimMacSpec(.A, .redesign, generation: 26, enabled: false, folder: nil, running: true, defaults: [Catalogue.hover: equal].merging(Catalogue.sectionsDefaults(Catalogue.pre(.A))) { first, _ in first }, syncedFolder: "F1"),
            SimMacSpec(.B, .redesign, generation: 27, running: true, defaults: [Catalogue.hover: equal].merging(layout) { first, _ in first }),
        ]
        let moved = Catalogue.scenario("S-14", macs: specs)
            .settle()
            // B founded the folder; A joins it with equal settings, then drags.
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 0)
            .expectSilent()
            .expectKey(.B, "MacOS27Layout", layout["MacOS27Layout"])
            .edit(.A, Catalogue.sectionsEntry, value: Catalogue.user(1, Catalogue.sectionsEntry))
            .settle()
            .expectSilent()
            .expectKey(.A, Catalogue.sections, .dictionary(["Visible": Catalogue.user(1, Catalogue.sectionsEntry)]))
            .expectKey(.B, "MacOS27Layout", layout["MacOS27Layout"])
            // A later move on B reaches no hint on A.
            .moveApp27(.B, bundle: Catalogue.appA, section: 2)
            .settle()
            .expectHint(.A, present: false)
            .expectNoLayoutQuestion()
            .expectPrompts(count: 0)
            .expectKey(.A, Catalogue.sections, .dictionary(["Visible": Catalogue.user(1, Catalogue.sectionsEntry)]))
        return Catalogue.run(moved)
    }

    // MARK: S-15

    // S-15 · A stale other-OS layout from a restored own version · A1 G3 · class: scope · source: V3-#0, step X (RC-4, RC-2, RC-3).
    static let s15: [CatalogueScenario] = [
        CatalogueScenario(id: "S-15/26", title: "A restored own version brings back no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS15(generation: 26)
        },
        CatalogueScenario(id: "S-15/27", title: "A restored own version never reverts a newer arrangement (generation 27)", source: .a1, kind: .scope) {
            runS15(generation: 27)
        },
    ]

    private static func runS15(generation: Int) -> SimScenarioResult {
        let v1 = CatalogueBox(-1)
        var scenario = Catalogue.scenario("S-15", macs: specs([.A, .C], generation: generation))
        // 1. C arranges L_C1; A changes a setting and writes V1, which holds C's layout as it is.
        scenario = arrange(scenario, .C, generation: generation, section: 1, k: 1).settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .markFile(of: .A, in: v1)
        // 2. C arranges L_C2, and A reads it.
        scenario = arrange(scenario, .C, generation: generation, section: 2, k: 2).settle()
        let arrangementC = CatalogueBox<SimValue?>(nil)
        scenario = scenario.perform("note C's arrangement") { world in
            arrangementC.value = Catalogue.value(world, .C, Catalogue.layoutA)
            return []
        }
        // 3. A sync app puts V1 back. 4. A quits, reopens and changes the setting. 5. C restarts through the hint.
        scenario = scenario
            .restoreFile(of: .A, to: v1)
            .settle()
            .restartApp(.A)
            .settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .settle()
            .restartApp(.C)
            .settle()
            .expectUser(.C, Catalogue.hover, 3)
            .expectUser(.A, Catalogue.hover, 3)
        scenario = common(scenario, generation: generation, drags: [.C: 2])
        if generation == 27 {
            scenario = scenario
                .expect("C keeps L_C2") { world in
                    Catalogue.value(world, .C, Catalogue.layoutA) == arrangementC.value ? nil : "C holds \(Catalogue.value(world, .C, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
                .expect("A never lists the older layout again") { world in
                    let listed = Catalogue.publishedEntries(world, .A, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                    return listed == [arrangementC.value].compactMap { $0 } ? nil : "A's file lists \(listed.map(\.canonical))"
                }
        }
        return Catalogue.run(scenario)
    }

    // MARK: S-16

    // S-16 · A stale other-OS layout from another Mac's older version · A1 G3 · class: scope · source: V3-#0 variant 2 (RC-4, RC-2).
    static let s16: [CatalogueScenario] = [
        CatalogueScenario(id: "S-16/26", title: "An older version of a third Mac brings back no arrangement (generation 26)", source: .a1, kind: .scope) {
            runS16(generation: 26)
        },
        CatalogueScenario(id: "S-16/27", title: "An older version of a third Mac never reverts a newer arrangement (generation 27)", source: .a1, kind: .scope) {
            runS16(generation: 27)
        },
    ]

    private static func runS16(generation: Int) -> SimScenarioResult {
        let v1 = CatalogueBox(-1)
        var scenario = Catalogue.scenario("S-16", macs: specs([.A, .B, .C], generation: generation))
        // B uploads V1, which holds C's first layout; C arranges again; A reads the newer one.
        scenario = arrange(scenario, .C, generation: generation, section: 1, k: 1).settle()
            .edit(.B, Catalogue.spacing, value: Catalogue.user(5, Catalogue.spacing))
            .settle()
            .markFile(of: .B, in: v1)
        scenario = arrange(scenario, .C, generation: generation, section: 2, k: 2).settle()
        let arrangementC = CatalogueBox<SimValue?>(nil)
        scenario = scenario
            .perform("note C's arrangement") { world in
                arrangementC.value = Catalogue.value(world, .C, Catalogue.layoutA)
                return []
            }
            .restartApp(.A)
            .settle()
            // The sync app keeps or delivers B's older upload again.
            .restoreFile(of: .B, to: v1)
            .settle()
            .restartApp(.A)
            .settle()
            .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .restartApp(.C)
            .settle()
            .expectUser(.C, Catalogue.hover, 3)
            .expectUser(.B, Catalogue.hover, 3)
            .expectUser(.A, Catalogue.spacing, 5)
        scenario = common(scenario, generation: generation, drags: [.C: 2])
        if generation == 27 {
            scenario = scenario
                .expect("every Mac holds L_C2") { world in
                    let held = [SimMacName.A, .B, .C].filter { Catalogue.value(world, $0, Catalogue.layoutA) != arrangementC.value }
                    return held.isEmpty ? nil : "\(held) do not hold the newest layout"
                }
        }
        return Catalogue.run(scenario)
    }

    // MARK: S-17

    // S-17 · Three Macs: the other-OS copy promoted to current · A1 G3 · class: scope · source: V4, step AF (RC-4, RC-5).
    static let s17: [CatalogueScenario] = [
        CatalogueScenario(id: "S-17/26", title: "A Mac that was off lists no arrangement over the others (generation 26)", source: .a1, kind: .scope) {
            runS17(generation: 26)
        },
        CatalogueScenario(id: "S-17/27", title: "A Mac that was off never lists its older layout over a newer one (generation 27)", source: .a1, kind: .scope) {
            runS17(generation: 27)
        },
    ]

    private static func runS17(generation: Int) -> SimScenarioResult {
        let arrangementC = CatalogueBox<SimValue?>(nil)
        func base(_ name: String) -> SimScenario {
            // All three Macs hold C's layout; D turns sync off.
            var scenario = Catalogue.scenario(name, macs: specs([.A, .C, .D], generation: generation))
            scenario = arrange(scenario, .C, generation: generation, section: 1, k: 1).settle()
                .restartApp(.A)
                .restartApp(.D)
                .settle()
                .turnOff(.D)
                .settle()
            // C arranges again while D is off, and A changes a setting.
            scenario = arrange(scenario, .C, generation: generation, section: 2, k: 2).settle()
                .perform("note C's arrangement") { world in
                    arrangementC.value = Catalogue.value(world, .C, Catalogue.layoutA)
                    return []
                }
                .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                .settle()
            return scenario
        }
        // D turns sync on again and changes a setting; C restarts through the hint.
        var unchanged = base("S-17")
            .turnOn(.D)
            .settle()
            .edit(.D, Catalogue.rehide, value: Catalogue.user(3, Catalogue.rehide))
            .settle()
            .restartApp(.C)
            .settle()
            .expectUser(.C, Catalogue.hover, 2)
            .expectUser(.C, Catalogue.rehide, 3)
        unchanged = common(unchanged, generation: generation, drags: [.C: 2])
        if generation == 27 {
            unchanged = unchanged
                .expect("C keeps its arrangement") { world in
                    Catalogue.value(world, .C, Catalogue.layoutA) == arrangementC.value ? nil : "C holds \(Catalogue.value(world, .C, Catalogue.layoutA)?.canonical ?? "nothing")"
                }
                .expect("D never lists its unchanged layout over C's") { world in
                    let newest = arrangementC.value
                    let listed = Catalogue.publishedEntries(world, .D, Catalogue.layoutA).compactMap(\.value).compactMap { SimValue(sync: $0) }
                    return listed.allSatisfy { $0 == newest } ? nil : "D's file lists \(listed.map(\.canonical))"
                }
        }
        guard generation == 27 else { return Catalogue.run(unchanged) }
        // If D's user rearranges as well, holzBar asks.
        let both = base("S-17 both rearrange")
            .moveApp27(.D, bundle: Catalogue.appA, section: 0)
            .turnOn(.D)
            .settle()
            .expect("D or C is asked about the arrangement") { world in
                Catalogue.layoutQuestions(world).contains(Catalogue.layoutA) ? nil : "nobody asked about \(Catalogue.layoutA)"
            }
            .expect("C keeps its arrangement until it is answered") { world in
                Catalogue.value(world, .C, Catalogue.layoutA) == arrangementC.value ? nil : "C holds \(Catalogue.value(world, .C, Catalogue.layoutA)?.canonical ?? "nothing")"
            }
        return Catalogue.combine("S-17", [unchanged, both].map(Catalogue.run))
    }

    // MARK: S-18 and S-19

    /// A macOS 27 Mac on the redesigned build and a macOS 26 Mac on 0.0.7-beta1 that holds an old copy of the arrangement
    /// and its own `ItemSections`.
    static func betaSpecs(oldCopy: Bool = true) -> [SimMacSpec] {
        var old = Catalogue.sectionsDefaults(Catalogue.pre(.C))
        if oldCopy {
            old.merge(Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 1, token: Catalogue.pre(.C))])) { first, _ in first }
        }
        return [
            SimMacSpec(.A, .redesign, generation: 27, running: true),
            SimMacSpec(.C, .beta1, generation: 26, running: true, defaults: old),
        ]
    }

    // S-18 · A beta1 Mac of the other OS writes an old copy back · A1 G3 · class: boundary · source: V1-#5, step O (RC-4, RC-7, RC-5).
    static let s18 = CatalogueScenario(id: "S-18", title: "A beta1 Mac writing an old arrangement back harms nobody", source: .a1, kind: .boundary) {
        let sections = Catalogue.sectionsDefaults(Catalogue.pre(.C))["ItemSections"]
        let scenario = Catalogue.scenario("S-18", macs: betaSpecs())
            .moveApp27(.A, bundle: Catalogue.appA, section: 1)
            .settle()
            .restartApp(.C)
            .advance(seconds: 30)
            .moveApp27(.A, bundle: Catalogue.appA, section: 2)
            .settle()
            // C changes a setting: beta1 writes its file, with the old copy.
            .edit(.C, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .advance(seconds: 30)
            .settle()
            .moveApp27(.A, bundle: Catalogue.appA, section: 3)
            .settle()
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectKey(.C, Catalogue.sections, sections)
            .expect("A's arrangement is its own latest move") { world in
                let held = Catalogue.value(world, .A, Catalogue.layoutA)
                guard case .dictionary(let entry)? = held else { return "A holds \(held?.canonical ?? "nothing")" }
                return entry["section"] == .int(3) ? nil : "A holds \(held?.canonical ?? "nothing")"
            }
            .expectOlderLine(.A, present: true)
            .expectBoundary(redesigned: [.A])
        return Catalogue.run(scenario)
    }

    // S-19 · The file is lost while a beta1 Mac of the other OS syncs · A1 G3 · class: boundary · source: V0-#3, V1-#6 (RC-4, RC-7) [CONFLICT C1].
    static let s19 = CatalogueScenario(id: "S-19", title: "A lost folder while a beta1 Mac syncs harms nobody", source: .a1, kind: .boundary) {
        let sections = Catalogue.sectionsDefaults(Catalogue.pre(.C))["ItemSections"]
        func lost(_ name: String, _ loss: SimProviderEvent) -> SimScenario {
            Catalogue.scenario(name, macs: betaSpecs(oldCopy: false))
                .moveApp27(.A, bundle: Catalogue.appA, section: 1)
                .edit(.C, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 30)
                .settle()
                .provider(loss)
                // A changes a setting and writes; C relaunches.
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .settle()
                .restartApp(.C)
                .settle()
                .expectPrompts(count: 0)
                .expectNoLayoutQuestion()
                .expectKey(.C, Catalogue.sections, sections)
                .expect("A still holds its arrangement") { world in
                    Catalogue.value(world, .A, Catalogue.layoutA) != nil ? nil : "A lost its arrangement"
                }
                .expectBoundary(redesigned: [.A])
        }
        let settings = lost("S-19 Settings.plist deleted", .delete(path: SimMacBeta1.filePath))
        let folder = lost("S-19 folder recreated", .deleteFolder())
            .expect("A writes its own file again") { world in
                Catalogue.ownPath(world, .A).map { path in world.replica(of: .A).entries[path] }.map { entry in
                    if case .present? = entry { true } else { false }
                } == true ? nil : "A's file did not come back"
            }
        return Catalogue.combine("S-19", [settings, folder].map(Catalogue.run))
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-13": CatalogueText(
            setup: "A runs macOS 27. B runs macOS 26 and was the only Mac writing the folder.",
            steps: "A applies B's file.",
            wrong: "Applying removes the keys B never had (MacOS27Layout, MacOS27LayoutSeeded, KnownApplications27) and A reseeds its layout; the other way the macOS 26 Mac loses ItemSections.",
            must: "Applying never removes a key the sender lacked. Each Mac keeps the layout of its own macOS version."
        ),
        "S-14": CatalogueText(
            setup: "A runs macOS 26 and B macOS 27, both on the redesigned build, with equal user settings.",
            steps: "B chooses an empty folder with Change…; A joins, then Command-drags.",
            wrong: "The layouts of the two macOS versions were compared, which led to questions; placements on either Mac caused hints.",
            must: "No question about layouts at any point. A's ItemSections stays A's, B's MacOS27Layout stays as it is."
        ),
        "S-15": CatalogueText(
            setup: "A runs macOS 26 and C macOS 27, both on the redesigned build.",
            steps: "A writes V1 with C's layout L_C1 as current. C drags (L_C2) and A reads it. V1 is put back. A quits, reopens and changes a setting. C restarts through the hint.",
            wrong: "A takes the stale L_C1 into its copy and writes it back as current; C applies it and its arrangement L_C2 is reverted.",
            must: "C keeps L_C2 and gets A's setting. A never takes in or lists again an other-OS layout that a newer version has replaced."
        ),
        "S-16": CatalogueText(
            setup: "As S-15, but the stale V1 is an earlier upload by a third Mac B that the sync app keeps or delivers again.",
            steps: "As S-15.",
            wrong: "Same outcome as S-15.",
            must: "Same as S-15."
        ),
        "S-17": CatalogueText(
            setup: "A runs macOS 26. C and D run macOS 27. All on the redesigned build.",
            steps: "D turns sync off. C drags. A changes a setting. D turns sync on again and changes a setting. C restarts through the hint.",
            wrong: "D's write lists its own older layout as current over the copy; C applies it silently and loses its arrangement.",
            must: "C keeps its arrangement. D never lists its unchanged layout over C's newer arrangement. If D's user rearranges as well, holzBar asks."
        ),
        "S-18": CatalogueText(
            setup: "A runs macOS 27 on the redesigned build. C runs macOS 26 on 0.0.7-beta1.",
            steps: "A arranges L1, then L2. C changes any setting: beta1 rewrites its file with the old copy. A drags.",
            wrong: "A asks about its own old layout and Use Settings from Sync Folder reverts A to L1.",
            must: "No question and no revert. A's layout stays current and C never loses its ItemSections."
        ),
        "S-19": CatalogueText(
            setup: "A runs macOS 27 on the redesigned build. C runs macOS 26 on 0.0.7-beta1.",
            steps: "Settings.plist is deleted or the folder is recreated. A changes a setting and writes. C relaunches.",
            wrong: "Without a copy the file lacks ItemSections and beta1 deletes C's at launch; with an old copy C applies it and its arrangement is reverted.",
            must: "C's arrangement survives. No content A can put into the legacy file achieves that, so the redesigned build never writes it."
        ),
    ]
}

/// The G3 scenarios, one test each.
@Suite("CatalogueG3Generations")
struct CatalogueG3GenerationsTests {
    @Test("A1 G3: two macOS versions", arguments: CatalogueG3Generations.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
