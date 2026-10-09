//
//  CatalogueG2Infrastructure.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// G2 of the A1 regression catalogue (S-09 to S-12): infrastructure. Online-only files, an unmounted share, files over
/// the size limit and malformed entries, on the real engine in the simulator.
nonisolated enum CatalogueG2Infrastructure {
    static let scenarios: [CatalogueScenario] = [s09, s10, s11, s12]

    static func pairSpecs() -> [SimMacSpec] {
        CatalogueG1Joining.pairSpecs()
    }

    /// The longest a launch may wait on the folder: about one second of simulated time (S-09).
    static let launchBudgetMilliseconds: Int64 = 1_000

    // MARK: S-09

    // S-09 · An online-only file at login · A1 G2 · class: pass · source: F-15 (RC-10, RC-3).
    static let s09 = CatalogueScenario(id: "S-09", title: "An online-only file at login never blocks the launch", source: .a1, kind: .pass) {
        // B's file is dataless on A and the network is down when A logs in.
        let dataless = Catalogue.scenario("S-09 dataless", macs: pairSpecs())
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .quit(.A)
            .edit(.B, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .evictFile(of: .B, on: .A)
            .offline(.A, seconds: 120)
            .launch(.A)
            .expect("the launch waits at most one second") { world in
                let blocked = Catalogue.launchHooks(world, .A).map(\.blockedMilliseconds).max() ?? 0
                return blocked <= launchBudgetMilliseconds ? nil : "the launch of A blocked \(blocked) ms"
            }
            .expect("the launch never reads a dataless file") { world in
                guard let path = Catalogue.ownPath(world, .B), let launch = Catalogue.launchHooks(world, .A).last else { return "A has no launch" }
                let read = launch.reads.first { $0.entry.path == path && { if case .data = $0.entry.result { true } else { false } }($0) }
                return read == nil ? nil : "the launch of A read the content of \(path)"
            }
            // The check after the launch applies the change once the file is on this Mac.
            .advance(seconds: 300)
            .settle()
            .expectHint(.A, present: true)
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
            .expectUser(.A, Catalogue.rehide, 2)
            .expectQuiet()

        // A hung provider: the launch still returns, and nothing waits on the main path.
        let hung = Catalogue.scenario("S-09 hung provider", macs: pairSpecs())
            .edit(.B, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .quit(.A)
            .provider(.stall(mac: .A, forMilliseconds: nil))
            .launch(.A)
            .expect("a hung provider holds the launch for one second at most") { world in
                let blocked = Catalogue.launchHooks(world, .A).map(\.blockedMilliseconds).max() ?? 0
                return blocked <= launchBudgetMilliseconds ? nil : "the launch of A blocked \(blocked) ms"
            }
            .expect("A is running") { world in world.state(of: .A).running ? nil : "A did not finish its launch" }
            .provider(.stall(mac: .A, forMilliseconds: 0))
            .restartApp(.A)
            .settle()
            .expectUser(.A, Catalogue.hover, 1)
        return Catalogue.combine("S-09", [dataless, hung].map(Catalogue.run))
    }

    // MARK: S-10

    // S-10 · The network share is not mounted · A1 G2 · class: pass · source: F-18 (RC-10).
    static let s10 = CatalogueScenario(id: "S-10", title: "An unmounted share is never mounted or written to", source: .a1, kind: .pass) {
        let unmounted = Catalogue.scenario("S-10", macs: pairSpecs())
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .restartApp(.B)
            .settle()
            .expectHint(.B, present: false)
            .provider(.unmount(mac: .A))
            .restartApp(.A)
            .settle()
            .expect("A says the sync folder cannot be found") { world in
                Catalogue.availability(world, .A) == .unavailable ? nil : "A's folder is \(String(describing: Catalogue.availability(world, .A)))"
            }
            .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
            .settle()
            .expect("nothing is written under the volume path") { world in
                world.violations.isEmpty ? nil : "\(world.violations.count) writes were attempted on the unmounted share"
            }
            .expectHint(.B, present: false)
            // The user mounts the share: syncing resumes and the change reaches B.
            .provider(.mount(mac: .A))
            .restartApp(.A)
            .settle()
            .expect("A finds the folder again") { world in
                Catalogue.availability(world, .A) == .available ? nil : "A's folder is \(String(describing: Catalogue.availability(world, .A)))"
            }
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 2)
            .expectPrompts(count: 0)
            .expectQuiet()
        return Catalogue.run(unmounted)
    }

    // MARK: S-11

    // S-11 · A settings file over the size limit · A1 G2 · class: pass · source: F-61, V0-#1 (RC-10, RC-1, RC-3).
    static let s11 = CatalogueScenario(id: "S-11", title: "A file over the size limit is refused, never overwritten, never ignored silently", source: .a1, kind: .pass) {
        // The writer refuses an encoding over 1 MiB, says so, and recovers when the settings are smaller again.
        // INV-Z3 is left out of this world: it reads the settings at the step of the edit, where the warning that
        // follows the capture two seconds later is not there yet. The same property is asserted after the capture.
        // INV-Z4 is left out too: its bound counts devices only, and a state that holds a megabyte of values is the
        // case this world makes.
        let writer = Catalogue.scenario("S-11 writer", macs: pairSpecs())
            .oracles(SimOracleSet.safety.without(["INV-Z3", "INV-Z4"]))
            .settle()
            .edit(.A, Catalogue.pads[0], value: Catalogue.big(1, Catalogue.pads[0], bytes: 400_000))
            .edit(.A, Catalogue.pads[1], value: Catalogue.big(1, Catalogue.pads[1], bytes: 400_000))
            .edit(.A, Catalogue.pads[2], value: Catalogue.big(1, Catalogue.pads[2], bytes: 400_000))
            .settle()
            .expect("A says its settings are too large") { world in
                Catalogue.lines(world, .A).contains(.tooLargeToPublish) ? nil : "A shows \(Catalogue.lines(world, .A))"
            }
            .expect("no file over the limit was written") { world in
                let largest = world.writeLog.map(\.data.count).max() ?? 0
                return largest <= SyncDeviceFile.maximumWriteSize ? nil : "a file of \(largest) bytes was written"
            }
            .expectHint(.B, present: false)
            // B changes a setting meanwhile (A1 step 3), which A takes in; then A makes its settings smaller.
            .edit(.B, Catalogue.rehide, value: Catalogue.user(1, Catalogue.rehide))
            .settle()
            .expectHint(.B, present: false)
            .delete(.A, Catalogue.pads[2])
            .settle()
            .expect("A writes again") { world in
                Catalogue.lines(world, .A).contains(.tooLargeToPublish) ? "A still shows the warning" : nil
            }
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.rehide, 1)
            .expectValue(.B, Catalogue.pads[0], Catalogue.big(1, Catalogue.pads[0], bytes: 400_000))
            .expectValue(.B, Catalogue.pads[1], Catalogue.big(1, Catalogue.pads[1], bytes: 400_000))

        // A reader never writes over a file it refused: another app put oversize bytes where A's file is. A waits,
        // and says that a file is unreadable.
        let refusedPath = CatalogueBox<String?>(nil)
        let writesBefore = CatalogueBox(0)
        func refusedWorld(_ name: String) -> SimScenario {
            Catalogue.scenario(name, macs: pairSpecs())
                .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
                .settle()
                .perform("note the file of A") { world in
                    refusedPath.value = Catalogue.ownPath(world, .A)
                    writesBefore.value = Catalogue.writes(world, by: .A, path: refusedPath.value).count
                    return []
                }
                .foreignFile(of: .A, .oversize)
                .advance(seconds: 30)
                .restartApp(.A)
                .advance(seconds: 30)
                .checkpoint()
                .edit(.A, Catalogue.rehide, value: Catalogue.user(2, Catalogue.rehide))
                .advance(seconds: 120)
                .expectNoWrite(.A)
                .expect("the refused file is shown as unreadable on A") { world in
                    Catalogue.lines(world, .A).contains(.unreadableFile) ? nil : "A shows \(Catalogue.lines(world, .A))"
                }
                .expectUser(.A, Catalogue.rehide, 2)
        }
        let refused = refusedWorld("S-11 refused file")
        // The refusal lasts ten minutes: A then goes on under a new identity and a new file, and never writes the
        // refused path. INV-ID2 is left out of this world: the engine marks the units of the new identity as
        // pre-existing instead of opening a join, which the oracle does not read as "joining again" (for plan 28-13).
        let lasting = refusedWorld("S-11 lasting refusal")
            .oracles(SimOracleSet.safety.without(["INV-ID2"]))
            .advance(seconds: 700)
            .restartApp(.A)
            .settle()
            .expect("the refused path is never written over") { world in
                let writes = Catalogue.writes(world, by: .A, path: refusedPath.value).count
                return writes == writesBefore.value ? nil : "A wrote \(refusedPath.value ?? "-") \(writes - writesBefore.value) times after it was refused"
            }
            .expect("A goes on under a file of its own") { world in
                Catalogue.ownPath(world, .A) != refusedPath.value ? nil : "A still uses the refused path"
            }
            .expectUser(.A, Catalogue.rehide, 2)


        // An oversize file written by a 0.0.7-beta1 peer is left alone; a Mac that joins goes on without it.
        let legacy = CatalogueBox<Data?>(nil)
        let peer = Catalogue.scenario(
            "S-11 beta1 file",
            macs: [
                SimMacSpec(.C, .beta1, generation: 26, running: true),
                SimMacSpec(.A, .redesign, generation: 26, enabled: false, folder: nil, running: true, defaults: [Catalogue.hover: Catalogue.pre(.A)], syncedFolder: "F1"),
            ]
        )
            .edit(.C, "ItemGroups", value: Catalogue.big(1, "ItemGroups", bytes: 1_100_000))
            .advance(seconds: 30)
            .perform("note the legacy file") { world in
                legacy.value = Catalogue.legacyBytes(world, as: .A)
                return legacy.value.map { $0.count > SettingsSyncFile.maximumFileSize ? [] : ["the beta1 file is only \($0.count) bytes"] } ?? ["the beta1 peer wrote no file"]
            }
            .turnOn(.A)
            .settle()
            .expectPrompts(count: 0)
            .expect("the legacy file is untouched") { world in
                Catalogue.legacyBytes(world, as: .A) == legacy.value ? nil : "the legacy file changed"
            }
            .expectBoundary(redesigned: [.A])
            .expect("A founded its own group") { world in
                Catalogue.publishedEntries(world, .A, Catalogue.hover).isEmpty ? "A published nothing" : nil
            }

        // A custom icon over 256 KiB stays on its Mac with the oversize note; every other unit still syncs.
        let icon = Catalogue.scenario("S-11 icon", macs: pairSpecs())
            .settle()
            .edit(.A, Catalogue.icon, value: Catalogue.big(1, Catalogue.icon, bytes: 300_000))
            .edit(.A, Catalogue.hover, value: Catalogue.user(1, Catalogue.hover))
            .settle()
            .expect("A shows the oversize note") { world in
                Catalogue.lines(world, .A).contains(.oversizeIcon) ? nil : "A shows \(Catalogue.lines(world, .A))"
            }
            .expectHint(.B, present: true)
            .restartApp(.B)
            .settle()
            .expectUser(.B, Catalogue.hover, 1)
            .expect("the icon stays on A") { world in
                Catalogue.value(world, .B, Catalogue.icon) == nil && Catalogue.value(world, .A, Catalogue.icon) != nil
                    ? nil : "the icon is on B or gone from A"
            }
            .expect("B shows no note") { world in
                Catalogue.lines(world, .B).contains(.oversizeIcon) ? "B shows the oversize note" : nil
            }
        return Catalogue.combine("S-11", [writer, refused, lasting, peer, icon].map(Catalogue.run))
    }

    // MARK: S-12

    // S-12 · A malformed entry in a synced setting · A1 G2 · class: pass · source: F-59 (RC-10).
    static let s12 = CatalogueScenario(id: "S-12", title: "A malformed entry is skipped, reported and never spread", source: .a1, kind: .pass) {
        let good = Catalogue.arrangement(section: 1, token: Catalogue.pre(.A))
        let badLayout = SimValue.dictionary(["section": .string("1")])
        let hotkey = SimValue.dictionary(["combo": .int(5), "token": Catalogue.pre(.A)])
        let layout = SimValue.dictionary([Catalogue.appA: good, Catalogue.appB: badLayout])
        let hotkeys = SimValue.dictionary(["toggle": hotkey, "broken": .string("not data")])

        // An imported file with a malformed entry on a Mac that joins: the entry stays on that Mac, unpublished and
        // unharmed, and the usable entries reach the other Mac.
        let specs = [
            SimMacSpec(
                .A, .redesign, generation: 27, enabled: false, folder: nil, running: true,
                defaults: ["MacOS27Layout": layout, "Hotkeys": hotkeys], syncedFolder: "F1"
            ),
            SimMacSpec(.B, .redesign, generation: 27, enabled: false, folder: nil, running: true, syncedFolder: "F1"),
        ]
        let local = Catalogue.scenario("S-12 local", macs: specs)
            .turnOn(.A)
            .settle()
            .turnOn(.B)
            .settle()
            .restartApp(.B)
            .settle()
            .expectPrompts(count: 0)
            .expectKey(.A, "MacOS27Layout", layout)
            .expectKey(.A, "Hotkeys", hotkeys)
            .expect("A keeps the malformed entries to itself") { world in
                let state = Catalogue.state(world, .A)
                var failures: [String] = []
                for unit in [Catalogue.layoutB, "Hotkeys/broken"] {
                    guard let key = SimEngineUnits.key(ofUnit: unit) else { continue }
                    if state?.localOnly[key] != .invalid { failures.append("\(unit) is not kept local") }
                    if !Catalogue.publishedEntries(world, .A, unit).isEmpty { failures.append("\(unit) was published") }
                }
                for unit in [Catalogue.layoutA, "Hotkeys/toggle"] where Catalogue.publishedEntries(world, .A, unit).isEmpty {
                    failures.append("\(unit) was not published")
                }
                return failures.isEmpty ? nil : failures.joined(separator: ", ")
            }
            .expect("B holds the usable entries and nothing else") { world in
                let held = world.defaults(of: .B)
                var failures: [String] = []
                if SimUnits.value(of: Catalogue.layoutA, in: held) != good { failures.append("B lacks \(Catalogue.layoutA)") }
                if SimUnits.value(of: Catalogue.layoutB, in: held) != nil { failures.append("B holds \(Catalogue.layoutB)") }
                if SimUnits.value(of: "Hotkeys/toggle", in: held) != hotkey { failures.append("B lacks Hotkeys/toggle") }
                if SimUnits.value(of: "Hotkeys/broken", in: held) != nil { failures.append("B holds Hotkeys/broken") }
                return failures.isEmpty ? nil : failures.joined(separator: ", ")
            }
            // A launch again changes nothing and loses nothing.
            .restartApp(.A)
            .settle()
            .expectKey(.A, "MacOS27Layout", layout)
            .expectKey(.A, "Hotkeys", hotkeys)
            .expectPrompts(count: 0)
            .expectQuiet()

        // A synced file with a malformed entry (a build that accepts more wrote it): the other Macs skip the entry and
        // report it as unusable, apply the rest, empty nothing and do not spread the loss.
        let synced = Catalogue.scenario(
            "S-12 synced",
            macs: [
                SimMacSpec(.A, .redesign, generation: 27, running: true),
                SimMacSpec(.B, .redesignSkew, generation: 27, running: true),
                SimMacSpec(.C, .redesign, generation: 27, running: true),
            ]
        )
            .moveApp27(.B, bundle: Catalogue.appA, section: 1)
            .edit(.B, Catalogue.layoutB, value: .dictionary(["section": .string("1"), "token": .userToken(9, unit: Catalogue.layoutB)]))
            .edit(.B, "Hotkeys/toggle", value: hotkey)
            .edit(.B, "Hotkeys/broken", value: .userToken(9, unit: "Hotkeys/broken"))
            .settle()
            .expect("A and C report an unusable value") { world in
                let missing = [SimMacName.A, .C].filter { !Catalogue.lines(world, $0).contains(.unusableValue) }
                return missing.isEmpty ? nil : "\(missing) show no unusable-value line"
            }
            .restartApp(.A)
            .restartApp(.C)
            .settle()
            .expect("A and C apply the usable entries and skip the malformed ones") { world in
                var failures: [String] = []
                for mac in [SimMacName.A, .C] {
                    let held = world.defaults(of: mac)
                    if SimUnits.value(of: Catalogue.layoutA, in: held) == nil { failures.append("\(mac) lacks \(Catalogue.layoutA)") }
                    if SimUnits.value(of: Catalogue.layoutB, in: held) != nil { failures.append("\(mac) holds \(Catalogue.layoutB)") }
                    if SimUnits.value(of: "Hotkeys/toggle", in: held) != hotkey { failures.append("\(mac) lacks Hotkeys/toggle") }
                    if SimUnits.value(of: "Hotkeys/broken", in: held) != nil { failures.append("\(mac) holds Hotkeys/broken") }
                }
                return failures.isEmpty ? nil : failures.joined(separator: ", ")
            }
            .expect("nobody deletes what it could not use") { world in
                for mac in [SimMacName.A, .C] {
                    for unit in [Catalogue.layoutB, "Hotkeys/broken", Catalogue.layoutA, "Hotkeys/toggle"] {
                        if Catalogue.publishedEntries(world, mac, unit).contains(where: { $0.payload == .deleted }) {
                            return "\(mac) published a deletion of \(unit)"
                        }
                    }
                }
                return nil
            }
            .expectPrompts(count: 0)
        return Catalogue.combine("S-12", [local, synced].map(Catalogue.run))
    }

    // MARK: Texts

    static let texts: [String: CatalogueText] = [
        "S-09": CatalogueText(
            setup: "A uses OneDrive, or iCloud Drive with Optimize Storage. B wrote the file, which is dataless on A.",
            steps: "Log in to A without network.",
            wrong: "The launch blocks on the coordinated read with no menu bar icon until the provider gives up; later a hung provider stalls the main thread at every push.",
            must: "The launch waits about one second at most and never reads a dataless or not yet current file. The check runs later in the background. No coordinated I/O on the main thread."
        ),
        "S-10": CatalogueText(
            setup: "A syncs through an SMB folder that is not mounted.",
            steps: "Launch A, change a setting, mount the share.",
            wrong: "holzBar mounts the share itself and blocks while the mount times out.",
            must: "Never mount. Show that the sync folder cannot be found, and resume once the user mounts the share."
        ),
        "S-11": CatalogueText(
            setup: "A and B on the redesigned build; a variant with A on 0.0.7-beta1.",
            steps: "Set a custom icon of 400 to 800 KB so the file passes 1 MiB; B changes any setting.",
            wrong: "B ignores every synced setting while the UI says it syncs; or B treats the file as unusable and writes over it without asking.",
            must: "The writer refuses content over the limit and says so. A reader never writes over a file it refused. An oversize file written by 0.0.7-beta1 is left alone."
        ),
        "S-12": CatalogueText(
            setup: "An imported or synced file holds MacOS27Layout with one value of 1.5 or \"1\", or a Hotkeys value that is not Data.",
            steps: "Apply it and relaunch.",
            wrong: "The whole dictionary is dropped, every app becomes visible, the user's next move writes a layout of one app to every Mac, and all hotkeys are lost.",
            must: "Validate each entry. A bad entry is skipped and never written back as a loss, and sync never spreads the loss to other Macs."
        ),
    ]
}

/// The G2 scenarios, one test each.
@Suite("CatalogueG2Infrastructure")
struct CatalogueG2InfrastructureTests {
    @Test("A1 G2: infrastructure", arguments: CatalogueG2Infrastructure.scenarios)
    func scenario(_ scenario: CatalogueScenario) async {
        await HeavyTestGate.run {
            Catalogue.check(scenario)
        }
    }
}
