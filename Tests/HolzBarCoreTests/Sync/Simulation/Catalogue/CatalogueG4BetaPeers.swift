//
//  CatalogueG4BetaPeers.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G4 of the A1 regression catalogue (S-20 to S-27): the same macOS version with a 0.0.7-beta1 Mac. Every scenario here
/// is a BOUNDARY scenario (analysis Appendix B): the redesigned build never shares a file with beta1, so the beta1 peer is
/// the literal `SimMacBeta1` algorithm (it writes `holzBar/Settings.plist` five seconds after any change, never reads
/// first, applies silently with key removal), and the scenario asserts that nothing is harmed on either side. What is
/// waived is that changes do not cross between the two builds; the only trace of the peer is the old-group status line.
///
/// Each scenario runs twice, on generation-26 Macs (the arrangement is `ItemSections`) and on generation-27 Macs (the
/// arrangement is `l27/*`, which syncs between redesigned Macs and is only a local key to beta1).
nonisolated enum CatalogueG4BetaPeers {
    static let scenarios: [CatalogueScenario] = [s20, s21, s22, s23, s24, s25, s26, s27]

    // MARK: Building blocks

    /// Runs a scenario on generation-26 Macs and on generation-27 Macs.
    static func both(_ id: String, _ build: (_ generation: Int) -> SimScenario) -> SimScenarioResult {
        bothWorlds(id) { [build($0)] }
    }

    /// The same, for a scenario of several worlds.
    static func bothWorlds(_ id: String, _ build: (_ generation: Int) -> [SimScenario]) -> SimScenarioResult {
        Catalogue.combine(id, [26, 27].flatMap { build($0) }.map(Catalogue.run))
    }

    static func redesigned(_ name: SimMacName, generation: Int, defaults: [String: SimValue] = [:]) -> SimMacSpec {
        SimMacSpec(name, .redesign, generation: generation, running: true, defaults: defaults)
    }

    /// The literal 0.0.7-beta1 peer (`SimMacBeta1`).
    static func peer(_ name: SimMacName, generation: Int, defaults: [String: SimValue] = [:]) -> SimMacSpec {
        SimMacSpec(name, .beta1, generation: generation, running: true, defaults: defaults)
    }

    /// The defaults of a Mac that holds an arrangement of its own: `ItemSections` on macOS 26, `MacOS27Layout` on macOS 27.
    static func arranged(_ token: SimValue, generation: Int) -> [String: SimValue] {
        generation == 27
            ? Catalogue.layoutDefaults([Catalogue.appA: Catalogue.arrangement(section: 1, token: token)])
            : Catalogue.sectionsDefaults(token)
    }

    /// One drag. A redesigned macOS 27 Mac moves an application in the Layout pane, which the engine captures as an intent;
    /// every other Mac changes the key it holds, with a token numbered `k` (above 100, so that it never meets the
    /// world's own numbering).
    static func drag(_ scenario: SimScenario, _ mac: SimMacName, generation: Int, redesigned: Bool, k: Int, section: Int = 1) -> SimScenario {
        if generation == 27 {
            return redesigned
                ? scenario.moveApp27(mac, bundle: Catalogue.appA, section: section)
                : scenario.edit(mac, Catalogue.layoutA, value: Catalogue.arrangement(section: section, token: Catalogue.user(k, Catalogue.layoutA)))
        }
        return scenario.edit(mac, Catalogue.sectionsEntry, value: Catalogue.user(k, Catalogue.sectionsEntry))
    }

    /// The beta1 peer has written its file by now.
    static func peerWrote(_ scenario: SimScenario, _ peer: SimMacName) -> SimScenario {
        scenario.expect("the beta1 peer \(peer) wrote the legacy file") { world in
            Catalogue.writes(world, by: peer, path: SimMacBeta1.filePath).isEmpty ? "\(peer) never wrote \(SimMacBeta1.filePath)" : nil
        }
    }

    // MARK: S-20

    // S-20 · A beta1 drag overwritten by an N Mac's non-layout write · A1 G4 · class: boundary · source: V0-#0, step A (RC-1, RC-7, RC-5).
    // Peer: SimMacBeta1 drags and writes the whole file; the redesigned Mac changes a setting; the peer relaunches.
    static let s20 = CatalogueScenario(id: "S-20", title: "A beta1 drag survives a redesigned Mac's write of a setting", source: .a1, kind: .boundary) {
        both("S-20") { generation in
            let dragged = CatalogueBox<SimValue?>(nil)
            let own = CatalogueBox<SimValue?>(nil)
            let scenario = Catalogue.scenario("S-20 generation \(generation)", macs: [redesigned(.A, generation: generation), peer(.B, generation: generation)])
            return peerWrote(
                drag(scenario, .B, generation: generation, redesigned: false, k: 101)
                    .noteArrangement(.A, generation: generation, in: own)
                    .advance(seconds: 30)
                    .settle()
                    .noteArrangement(.B, generation: generation, in: dragged),
                .B
            )
            // A changes a setting and writes; B quits and reopens.
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .advance(seconds: 30)
            .settle()
            // B keeps its drag, A's arrangement is A's, and a drag on A replaces nothing of B's.
            .expectArrangement(.B, generation: generation, is: dragged)
            .expectArrangement(.A, generation: generation, is: own)
            .expect("the setting stays on A: beta1 does not read the redesigned files") { world in
                Catalogue.value(world, .B, Catalogue.hover) == nil ? nil : "B holds \(Catalogue.value(world, .B, Catalogue.hover)?.canonical ?? "")"
            }
            .expect("B shows no alert") { world in world.brains[.B]?.openPrompt == nil ? nil : "B shows the alert of the old build" }
            .perform("a drag on A") { world in
                world.step(generation == 27
                    ? .moveApp27(mac: .A, bundle: Catalogue.appA, section: 2)
                    : .userEdit(mac: .A, unit: Catalogue.sectionsEntry, value: Catalogue.user(102, Catalogue.sectionsEntry)))
                return []
            }
            .settle()
            .expectArrangement(.B, generation: generation, is: dragged)
            .expectPrompts(count: 0)
            .expectNoLayoutQuestion()
            .expectOlderLine(.A, present: true)
            .expectBoundary(redesigned: [.A])
        }
    }

    // MARK: S-21

    // S-21 · A beta1 Mac updated to N adopts the other Mac's layout · A1 G4 · class: boundary · source: V0-#0 variant (RC-7, RC-6).
    // Peer: SimMacBeta1 is updated to the redesigned build and joins the group of a redesigned Mac.
    static let s21 = CatalogueScenario(id: "S-21", title: "A beta1 Mac updated to the redesigned build joins and keeps its arrangement", source: .a1, kind: .boundary) {
        both("S-21") { generation in
            let own = CatalogueBox<SimValue?>(nil)
            let scenario = Catalogue.scenario(
                "S-21 generation \(generation)",
                macs: [
                    redesigned(.A, generation: generation),
                    peer(.B, generation: generation, defaults: arranged(Catalogue.pre(.B), generation: generation).merging([Catalogue.hover: Catalogue.pre(.B)]) { first, _ in first }),
                ]
            )
            var steps = scenario.edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            if generation == 27 {
                steps = steps.moveApp27(.A, bundle: Catalogue.appA, section: 2)
            }
            return steps
                .advance(seconds: 30)
                .settle()
                .noteArrangement(.B, generation: generation, in: own)
                // B updates to the redesigned build: it has no state, so it joins A's group.
                .updateApp(.B, .redesign)
                .launch(.B)
                .settle()
                .expectPrompts(count: 1, mac: .B)
                .expect("B asks about the setting that differs") { world in
                    Catalogue.shownUnits(world, .B).contains(Catalogue.hover) ? nil : "B's sheet shows \(Catalogue.shownUnits(world, .B))"
                }
                .expect("B asks about its arrangement only on macOS 27, where it counts as its own") { world in
                    let asked = Catalogue.layoutQuestions(world).contains(Catalogue.layoutA)
                    return asked == (generation == 27) ? nil : "the arrangement was \(asked ? "" : "not ")asked about on generation \(generation)"
                }
                .expectArrangement(.B, generation: generation, is: own)
                .answer(.B, .keep)
                .settle()
                .expectArrangement(.B, generation: generation, is: own)
                .expectValue(.B, Catalogue.hover, Catalogue.pre(.B))
                .expectBoundary(redesigned: [.A, .B], sheets: 1, hints: true)
        }
    }

    // MARK: S-22

    // S-22 · An N Mac with its own arrangement joins a folder written by beta1 · A1 G4 · class: boundary · source: V0-#0 joining variant, step B (RC-7, RC-5).
    // Peer: SimMacBeta1 wrote the folder's legacy file; the redesigned Mac founds a group from it once.
    static let s22 = CatalogueScenario(id: "S-22", title: "A redesigned Mac founds from a beta1 file once and keeps its arrangement", source: .a1, kind: .boundary) {
        bothWorlds("S-22") { generation in
            let own = CatalogueBox<SimValue?>(nil)
            let legacy = CatalogueBox<Data?>(nil)
            let foreign = Catalogue.scenario(
                "S-22 generation \(generation)",
                macs: [
                    peer(.B, generation: generation, defaults: arranged(Catalogue.pre(.B), generation: generation).merging([Catalogue.hover: Catalogue.pre(.B)]) { first, _ in first }),
                    SimMacSpec(
                        .C, .redesign, generation: generation, enabled: false, folder: nil, running: true,
                        defaults: arranged(Catalogue.pre(.C), generation: generation).merging([Catalogue.hover: Catalogue.pre(.C)]) { first, _ in first },
                        syncedFolder: "F1"
                    ),
                ]
            )
                .advance(seconds: 30)
                .noteArrangement(.C, generation: generation, in: own)
                .perform("note the legacy file") { world in
                    legacy.value = Catalogue.legacyBytes(world, as: .C)
                    return legacy.value == nil ? ["the beta1 peer wrote no file"] : []
                }
                .turnOn(.C)
                .settle()
                // C asks where the settings differ, and never about the arrangement of the beta1 file.
                .expectPrompts(count: 1, mac: .C)
                .expect("C asks about the setting") { world in
                    Catalogue.shownUnits(world, .C) == [Catalogue.hover] ? nil : "C's sheet shows \(Catalogue.shownUnits(world, .C))"
                }
                .expectNoLayoutQuestion()
                .expectArrangement(.C, generation: generation, is: own)
                .answer(.C, .keep)
                .settle()
                .expectArrangement(.C, generation: generation, is: own)
                .expectValue(.C, Catalogue.hover, Catalogue.pre(.C))
                .expect("the legacy file is untouched") { world in
                    Catalogue.legacyBytes(world, as: .C) == legacy.value ? nil : "the legacy file changed"
                }
                .expectBoundary(redesigned: [.C], sheets: 1)
            // A beta1 Mac updated to the redesigned build ignores the file it wrote itself.
            let updated = Catalogue.scenario(
                "S-22 own file generation \(generation)",
                macs: [peer(.B, generation: generation, defaults: arranged(Catalogue.pre(.B), generation: generation).merging([Catalogue.hover: Catalogue.pre(.B)]) { first, _ in first })]
            )
                .advance(seconds: 30)
                .updateApp(.B, .redesign)
                .launch(.B)
                .settle()
                .expectPrompts(count: 0)
                .expectSilent()
                .expect("B founded its group from its own settings") { world in
                    Catalogue.publishedEntries(world, .B, Catalogue.hover).isEmpty ? "B published no entry for \(Catalogue.hover)" : nil
                }
                .expectBoundary(redesigned: [.B])
            return [foreign, updated]
        }
    }

    // MARK: S-23

    // S-23 · A kept arrangement written back by beta1 · A1 G4 · class: boundary · source: V2-#5, step T (RC-5, RC-7, RC-8).
    // Peer: SimMacBeta1 relaunches and changes a setting while two redesigned Macs settle a conflict.
    static let s23 = CatalogueScenario(id: "S-23", title: "A kept answer is not undone by a beta1 write", source: .a1, kind: .boundary) {
        both("S-23") { generation in
            let dragged = CatalogueBox<SimValue?>(nil)
            let sheetsBeforePeer = CatalogueBox(0)
            var scenario = Catalogue.scenario(
                "S-23 generation \(generation)",
                macs: [redesigned(.A, generation: generation), redesigned(.B, generation: generation), peer(.C, generation: generation)]
            )
                .offline(.A, seconds: 3_600)
            // B drags and changes the setting; A changes it the other way; A keeps its own.
            scenario = drag(scenario, .B, generation: generation, redesigned: true, k: 101, section: 1)
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .edit(.A, Catalogue.hover, value: Catalogue.user(2, Catalogue.hover))
                .advance(seconds: 30)
                .online(.A)
                .settle()
                .answer(.A, .keep)
                .settle()
                .noteArrangement(.B, generation: generation, in: dragged)
                .perform("count the sheets so far") { world in
                    sheetsBeforePeer.value = Catalogue.promptCount(world)
                    return []
                }
                // C relaunches and changes a setting: beta1 writes its file.
                .restartApp(.C)
                .edit(.C, Catalogue.spacing, value: Catalogue.user(7, Catalogue.spacing))
                .advance(seconds: 30)
                .settle()
                // A changes the setting again, B quits and reopens.
                .edit(.A, Catalogue.hover, value: Catalogue.user(3, Catalogue.hover))
                .settle()
                .restartApp(.B)
                .settle()
                .expectArrangement(.B, generation: generation, is: dragged)
                .expect("the beta1 write opened no sheet") { world in
                    Catalogue.promptCount(world) == sheetsBeforePeer.value ? nil : "\(Catalogue.promptCount(world) - sheetsBeforePeer.value) sheets after the beta1 write"
                }
                .expect("the beta1 Mac holds none of the redesigned settings") { world in
                    Catalogue.value(world, .C, Catalogue.hover) == nil ? nil : "C holds \(Catalogue.value(world, .C, Catalogue.hover)?.canonical ?? "")"
                }
            if generation == 27 {
                // The answer took B's layout in, so A's drag is a new change of the layout: B keeps its own until it
                // restarts, and is told.
                scenario = scenario
                    .expectArrangement(.A, generation: generation, is: dragged)
                    .moveApp27(.A, bundle: Catalogue.appA, section: 2)
                    .settle()
                    .expectArrangement(.B, generation: generation, is: dragged)
                    .expectHint(.B, present: true)
            }
            return scenario.expectBoundary(redesigned: [.A, .B], sheets: nil, hints: true)
        }
    }

    // MARK: S-24

    // S-24 · beta1 keeps writing an old copy while N rearranges · A1 G4 · class: boundary · source: V2-#3, step U (RC-5, RC-7).
    // Peer: SimMacBeta1 holds an old copy of the arrangement and writes it back after every change.
    static let s24 = CatalogueScenario(id: "S-24", title: "A beta1 Mac writing an old copy back never reverts a redesigned Mac's layout", source: .a1, kind: .boundary) {
        both("S-24") { generation in
            let old = CatalogueBox<SimValue?>(nil)
            var scenario = Catalogue.scenario(
                "S-24 generation \(generation)",
                macs: [redesigned(.A, generation: generation), peer(.C, generation: generation, defaults: arranged(Catalogue.pre(.C), generation: generation))]
            )
                .noteArrangement(.C, generation: generation, in: old)
            // A rearranges twelve times and lets each write.
            for step in 0..<12 {
                scenario = drag(scenario, .A, generation: generation, redesigned: true, k: 200 + step, section: step % 3).advance(seconds: 10)
            }
            scenario = scenario.settle()
                // C changes a setting: beta1 writes the old copy back.
                .restartApp(.C)
                .edit(.C, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .advance(seconds: 30)
                .settle()
            scenario = drag(scenario, .A, generation: generation, redesigned: true, k: 300, section: 1).settle()
            return scenario
                .expectPrompts(count: 0)
                .expectNoLayoutQuestion()
                .expectArrangement(.C, generation: generation, is: old)
                .expect("A's layout is current") { world in
                    Catalogue.arrangement(world, .A, generation: generation) != nil ? nil : "A holds no arrangement"
                }
                .expectOlderLine(.A, present: true)
                .expectBoundary(redesigned: [.A])
        }
    }

    // MARK: S-25

    // S-25 · A beta1 user goes back to an earlier arrangement · A1 G4 · class: boundary · source: V3-#6, V4 (RC-5, RC-7) [CONFLICT C2].
    // Peer: SimMacBeta1 moves the items back to exactly an earlier arrangement and writes the file.
    static let s25 = CatalogueScenario(id: "S-25", title: "A beta1 user's return to an earlier arrangement is never reverted", source: .a1, kind: .boundary) {
        both("S-25") { generation in
            let returned = CatalogueBox<SimValue?>(nil)
            var scenario = Catalogue.scenario(
                "S-25 generation \(generation)",
                macs: [redesigned(.A, generation: generation), peer(.C, generation: generation)]
            )
            scenario = drag(scenario, .A, generation: generation, redesigned: true, k: 101, section: 1).settle()
            scenario = drag(scenario, .A, generation: generation, redesigned: true, k: 102, section: 2).settle()
            // C moves the items back to the first arrangement and writes.
            scenario = drag(scenario, .C, generation: generation, redesigned: false, k: 103, section: 1)
                .advance(seconds: 30)
                .noteArrangement(.C, generation: generation, in: returned)
                // A changes a setting; C quits and reopens; A drags.
                .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
                .restartApp(.C)
                .advance(seconds: 30)
                .settle()
            scenario = drag(scenario, .A, generation: generation, redesigned: true, k: 104, section: 3).settle()
            return scenario
                .expectArrangement(.C, generation: generation, is: returned)
                .expectPrompts(count: 0)
                .expectNoLayoutQuestion()
                .expectBoundary(redesigned: [.A])
        }
    }

    // MARK: S-26

    // S-26 · A beta1 write over a deleted or damaged file · A1 G4 · class: boundary · source: R4/R5 residual (RC-7, RC-3) [CONFLICT C2].
    // Peer: SimMacBeta1 writes a legacy file that carries no change of the redesigned Macs.
    static let s26 = CatalogueScenario(id: "S-26", title: "A beta1 write over a deleted file never reverts a redesigned Mac's change", source: .a1, kind: .boundary) {
        both("S-26") { generation in
            Catalogue.scenario(
                "S-26 generation \(generation)",
                macs: [redesigned(.A, generation: generation), redesigned(.B, generation: generation), peer(.C, generation: generation)]
            )
                .advance(seconds: 30)
                // B changes a setting; before the others read it the legacy file is deleted.
                .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .provider(.delete(path: SimMacBeta1.filePath))
                // C changes a setting: beta1 writes a file without B's change.
                .edit(.C, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 30)
                .settle()
                .restartApp(.A)
                .restartApp(.B)
                .settle()
                .expectUser(.B, Catalogue.hover, 1)
                .expectUser(.A, Catalogue.hover, 1)
                .expect("the beta1 Mac's setting stays on the beta1 Mac") { world in
                    Catalogue.value(world, .A, Catalogue.rehide) == nil && Catalogue.value(world, .B, Catalogue.rehide) == nil ? nil : "a redesigned Mac holds \(Catalogue.rehide)"
                }
                .expectPrompts(count: 0)
                .expectOlderLine(.A, present: true)
                .expectBoundary(redesigned: [.A, .B])
        }
    }

    // MARK: S-27

    // S-27 · beta1 rewrites at launch and after automatic changes in a mixed set of Macs · A1 G4 · class: boundary · source: F-02(b)/(c) (RC-7, RC-6).
    // Peer: SimMacBeta1 relaunches a hundred times and learns items, which is an automatic write five seconds later.
    static let s27 = CatalogueScenario(id: "S-27", title: "A hundred beta1 rewrites leave one status line and no question", source: .a1, kind: .boundary) {
        both("S-27") { generation in
            var scenario = Catalogue.scenario(
                "S-27 generation \(generation)",
                macs: [redesigned(.A, generation: generation), redesigned(.B, generation: generation), peer(.C, generation: generation)]
            )
                .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
                .restartApp(.B)
                .settle()
                .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .settle()
                .restartApp(.A)
                .settle()
                .checkpoint()
            for round in 0..<100 {
                scenario = scenario.restartApp(.C).advance(seconds: 6)
                if round.isMultiple(of: 10) {
                    scenario = scenario.learn(.C, "KnownItemTags").advance(seconds: 6)
                }
            }
            return scenario
                .settle()
                .expectNoWrite(.A)
                .expectNoWrite(.B)
                .expectUser(.A, Catalogue.hover, 1)
                .expectUser(.A, Catalogue.rehide, 2)
                .expectUser(.B, Catalogue.hover, 1)
                .expectUser(.B, Catalogue.rehide, 2)
                .expect("each redesigned Mac shows the one old-group line and nothing else") { world in
                    var failures: [String] = []
                    for mac in [SimMacName.A, .B] where Catalogue.lines(world, mac) != [.olderHolzBar] {
                        failures.append("\(mac) shows \(Catalogue.lines(world, mac))")
                    }
                    return failures.isEmpty ? nil : failures.joined(separator: ", ")
                }
                .expectPrompts(count: 0)
                .expectBoundary(redesigned: [.A, .B])
        }
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-20": CatalogueText(
            setup: "A runs the redesigned build and has synced. B runs 0.0.7-beta1, same macOS. Two macOS 27 Macs behave the same.",
            steps: "B drags an item and beta1 writes the whole file. A changes Show on hover and writes. B quits and reopens.",
            wrong: "A writes its own older layout as current; beta1 B applies it silently at launch and B's drag is reverted.",
            must: "B keeps its drag. A's write of a setting never replaces a layout A did not arrange. A drag on A that would replace B's layout asks first."
        ),
        "S-21": CatalogueText(
            setup: "As S-20: A on the redesigned build, B on 0.0.7-beta1.",
            steps: "B updates to the redesigned build instead of relaunching on beta1.",
            wrong: "The migration seeds no edits because B syncs; B joins and the adopt branch applies A's layout silently over B's drag.",
            must: "B's arrangement survives. It counts as the user's, and holzBar asks if it differs."
        ),
        "S-22": CatalogueText(
            setup: "B runs 0.0.7-beta1 and wrote the folder with its layout. C runs the redesigned build and has an arrangement of its own.",
            steps: "Turn sync on on C.",
            wrong: "C writes its layout over B's without asking.",
            must: "C asks where the settings differ. The arrangement of the legacy file is never applied; a file C's own earlier build wrote is ignored."
        ),
        "S-23": CatalogueText(
            setup: "A and B on the redesigned build, C on 0.0.7-beta1, all on the same macOS.",
            steps: "B drags and changes Show on hover; A changes it the other way and chooses Keep. C reopens and changes a setting. A changes Show on hover. B quits and reopens.",
            wrong: "A read C's write-back of the kept layout as its own old copy and wrote its own layout as current; B applied it silently and lost its arrangement.",
            must: "B keeps its arrangement, and a drag on A asks."
        ),
        "S-24": CatalogueText(
            setup: "A runs macOS 27 on the redesigned build. C runs 0.0.7-beta1.",
            steps: "A arranges and writes, ten times or more. C changes a setting and beta1 writes A's old copy back. A drags.",
            wrong: "A asks about its own old layout.",
            must: "No question; A's layout is current. C's ItemSections stays as it is."
        ),
        "S-25": CatalogueText(
            setup: "A on the redesigned build and C on 0.0.7-beta1, same macOS. A synced L1, then L2.",
            steps: "C moves the items back to exactly L1 and writes. A changes a setting. C quits and reopens. A drags.",
            wrong: "A's write put L2 back over C's deliberate return, silently.",
            must: "C's return is never reverted silently. If A then rearranges, both Macs changed the layout and holzBar asks, or the design makes the case decidable."
        ),
        "S-26": CatalogueText(
            setup: "A and B on the redesigned build, C on 0.0.7-beta1.",
            steps: "B changes a setting. Before the others read it Settings.plist is deleted. C changes a setting and beta1 writes a file without B's change. A and B check.",
            wrong: "C's file carries no causal metadata; B has no changes and takes it without asking, so B's change is reverted silently.",
            must: "B's change is not reverted silently."
        ),
        "S-27": CatalogueText(
            setup: "A and B on the redesigned build. C on 0.0.7-beta1.",
            steps: "C relaunches, so beta1 rewrites the file with a fresh date. C learns a new item, an automatic write five seconds later.",
            wrong: "The redesigned Macs show a hint or a question for content that did not change, or treat C's rewrite as a user change that replaces their own newer ones.",
            must: "The redesigned Macs show nothing but one status line, and C's rewrite never displaces their newer user changes."
        ),
    ]
}

/// The G4 scenarios, one test each.
@Suite("CatalogueG4BetaPeers")
struct CatalogueG4BetaPeersTests {
    @Test("A1 G4: the same macOS version with a beta1 Mac", arguments: CatalogueG4BetaPeers.scenarios)
    func scenario(_ scenario: CatalogueScenario) {
        Catalogue.check(scenario)
    }
}
