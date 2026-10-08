//
//  CatalogueSupport.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

// MARK: - The scenario type

/// Where a catalogue scenario comes from: the A1 failure taxonomy, the A2 requirements, the D3 walk or the judges.
enum CatalogueSource: String, Hashable, Sendable {
    case a1
    case a2
    case d3
    case judge
}

/// How analysis Appendix B classes a scenario for this phase.
enum CatalogueKind: String, Hashable, Sendable {
    /// Holds as written.
    case pass
    /// Layout propagation: runs for generation-26 Macs (the layout keys untouched) and in its macOS 27 form.
    case scope
    /// A real 0.0.7-beta1 peer takes part: nothing may be harmed on either side.
    case boundary
    /// Added by a review round, not in A1.
    case added
}

/// A scenario of the regression catalogue: a fixed test on the real engine in the simulator.
nonisolated struct CatalogueScenario: Sendable, CustomTestStringConvertible {
    let id: String
    let title: String
    let source: CatalogueSource
    let kind: CatalogueKind
    let run: @Sendable () -> SimScenarioResult

    var testDescription: String { "\(id) \(title)" }
}

/// The A1 text of a scenario, as its failure message prints it (A1 section 6: Setup, Steps, Wrong, Must).
nonisolated struct CatalogueText: Sendable {
    let setup: String
    let steps: String
    let wrong: String
    let must: String
}

// MARK: - The harness

/// Builders, shared expectations and the failure message of the catalogue scenarios (plans 28-10 to 28-12).
///
/// A catalogue world uses one unit table of real setting names (the beta1 peer's file must carry units
/// the redesigned engine can found a group from), the safety and layout oracles, and the real engine on
/// every redesigned Mac. A scenario's final step is always `expectNoViolation()` over all of them.
nonisolated enum Catalogue {
    // MARK: Units

    /// "Show on hover", the setting the A1 steps change.
    static let hover = "ShowOnHover"
    /// Other plain settings.
    static let shelf = "UseIceBar"
    static let menus = "HideApplicationMenus"
    static let spacing = "ItemSpacingOffset"
    static let rehide = "RehideInterval"
    /// One hotkey of the split family.
    static let hotkey = "Hotkeys/toggle"
    /// The two applications the macOS 27 arrangement scenarios move.
    static let appA = "com.app.a"
    static let appB = "com.app.b"
    static let layoutA = "l27/com.app.a"
    static let layoutB = "l27/com.app.b"
    /// The macOS 26 arrangement, a local key that never syncs.
    static let sections = "ItemSections"
    static let sectionsEntry = "ItemSections/Visible"

    /// The custom icon, a unit of its own with the cap of the real table (256 KiB).
    static let icon = "HolzBarIcon"
    /// Units that take values of hundreds of KiB, so that a few of them make a file over the 1 MiB limit.
    static let pads = ["Pad1", "Pad2", "Pad3"]

    static let wholeUnits = [hover, shelf, menus, spacing, rehide]

    /// The unit table of the catalogue: the real names of the settings the beta1 peer's file carries, the icon with its
    /// cap, three units with a large cap, one split family of hotkeys and the macOS 27 families, scoped as in the app.
    /// A hotkey is usable when it is a dictionary with a whole `combo`, an entry of `l27` when it is a section number.
    static let table = makeTable(strict: true)

    /// The same table of a build that accepts every value, which is how a value another build wrote can be unusable here
    /// (S-12).
    static let laxTable = makeTable(strict: false)

    private static func makeTable(strict: Bool) -> SyncUnitTable {
        var descriptors = wholeUnits.map { descriptor($0, cap: 1 << 10) }
        descriptors.append(descriptor(icon, cap: 256 << 10))
        descriptors += pads.map { descriptor($0, cap: 600 << 10) }
        descriptors.append(descriptor(SimEngineUnits.family, cap: 4 << 10, family: true) { _, value in
            if !strict { return true }
            if case .integer? = value.dictionaryValue?["combo"] { return true }
            return false
        })
        descriptors.append(descriptor(SyncUnitTable.layout27Family, cap: 1 << 10, family: true, scope: .g27) { _, value in
            if !strict { return true }
            if case .integer = value { return true }
            if case .integer? = value.dictionaryValue?["section"] { return true }
            return false
        })
        descriptors.append(descriptor(SyncUnitTable.profilesFamily, cap: 64 << 10, family: true, scope: .g27))
        descriptors.append(descriptor(SyncUnitTable.knownApplicationsSet, cap: 0, scope: .g27, isSet: true))
        return SyncUnitTable(version: 1, descriptors: descriptors)
    }

    private static func descriptor(
        _ name: String,
        cap: Int,
        family: Bool = false,
        scope: SyncGeneration? = nil,
        isSet: Bool = false,
        validate: @escaping @Sendable (String?, SyncValue) -> Bool = { _, _ in true }
    ) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [],
            cap: cap,
            maximumItems: family ? SyncDeviceFile.maximumEntriesPerFamily : nil,
            scope: scope,
            isSet: isSet,
            isFamily: family,
            measure: { $0.encodedSize },
            validate: validate
        )
    }

    /// A value of about `bytes` bytes that still carries the token of its unit: JSON as the icon and the large units hold.
    static func big(_ k: Int, _ unit: String, bytes: Int) -> SimValue {
        let json = "{\"token\":\"u\(k)@\(unit)\",\"pad\":\"\(String(repeating: "x", count: bytes))\"}"
        return .data(Data(json.utf8))
    }

    /// The user's value number `k` of a unit (the world's own counter starts at 1, so scenarios that name their
    /// values use these and never `edit` without a value on the same unit).
    static func user(_ k: Int, _ unit: String) -> SimValue { .userToken(k, unit: unit) }

    /// A value that was there before the Mac's first redesigned run.
    static func pre(_ mac: SimMacName) -> SimValue { .preToken(mac: mac) }

    /// One application's entry of the macOS 27 arrangement: the section and the token that names its origin.
    static func arrangement(section: Int, token: SimValue) -> SimValue {
        .dictionary(["section": .int(section), "token": token])
    }

    /// The defaults of a macOS 27 Mac that holds these entries of `MacOS27Layout` (bundle identifier to entry).
    static func layoutDefaults(_ entries: [String: SimValue]) -> [String: SimValue] {
        ["MacOS27Layout": .dictionary(entries)]
    }

    /// The defaults of a macOS 26 Mac that holds this arrangement (`ItemSections`, one entry per section).
    static func sectionsDefaults(_ token: SimValue) -> [String: SimValue] {
        [sections: .dictionary(["Visible": token])]
    }

    // MARK: Worlds

    /// Which brain a Mac of a build gets: the real engine on this catalogue's unit table, the real beta1 peer.
    static func brain(_ version: SimMacVersion, _ mac: SimMacName) -> any SimSyncBrain {
        switch version {
        case .redesign: SimMacRedesign(table: table)
        case .redesignSkew: SimMacRedesign(table: laxTable)
        case .beta1: SimMacBeta1()
        case .beta2: SimMacBeta2()
        }
    }

    /// Macs that run with sync on in the folder `F1`: a name, a build and the generation of macOS.
    static func specs(_ macs: [(SimMacName, SimMacVersion, Int)]) -> [SimMacSpec] {
        macs.map { SimMacSpec($0.0, $0.1, generation: $0.2, running: true) }
    }

    /// A world of running Macs, under the safety and layout oracles.
    static func world(macs: [(SimMacName, SimMacVersion, Int)], preset: SimProviderPreset? = nil, seed: UInt64 = 1) -> SimWorld {
        SimWorld(seed: seed, macs: specs(macs), preset: preset, brainFactory: brain, oracles: .safety)
    }

    /// A scenario of the DSL on the real engine and the safety and layout oracles.
    static func scenario(_ name: String, seed: UInt64 = 1, preset: SimProviderPreset? = nil, macs: [SimMacSpec]) -> SimScenario {
        SimScenario(name, seed: seed, preset: preset).macs(macs).brains(brain).oracles(.safety)
    }

    /// Runs a scenario with the oracle check as its last step.
    static func run(_ scenario: SimScenario) -> SimScenarioResult {
        scenario.expectNoViolation().run()
    }

    /// The results of several worlds of one scenario as one: every failure, and the last world.
    static func combine(_ id: String, _ results: [SimScenarioResult]) -> SimScenarioResult {
        SimScenarioResult(name: id, failures: results.flatMap(\.failures), world: results[results.count - 1].world)
    }

    // MARK: Time

    /// Delivers everything and lets every timer run, then lets the 15-minute poll run twice.
    static func settle(_ world: SimWorld) {
        SimDrain.settle(world)
        world.advance(seconds: 16 * 60)
        SimDrain.settle(world)
    }

    /// Restarts every running Mac in name order and settles after each, until a whole round writes nothing and
    /// opens nothing (at most six rounds).
    static func relaunchUntilQuiet(_ world: SimWorld) {
        for _ in 0..<6 {
            let writes = world.writeLog.count
            let prompts = promptCount(world)
            for mac in world.macs.keys.sorted() where world.macs[mac]?.running == true {
                world.step(.restartApp(mac: mac))
                settle(world)
            }
            if world.writeLog.count == writes, promptCount(world) == prompts {
                return
            }
        }
    }

    /// The number of sheets every Mac has opened so far.
    static func promptCount(_ world: SimWorld) -> Int {
        world.allSteps.flatMap(\.prompts).count
    }

    /// Whether no Mac shows a hint or a sheet now.
    static func silent(_ world: SimWorld) -> [String] {
        var failures: [String] = []
        for mac in world.macs.keys.sorted() where world.macs[mac]?.running == true {
            if let hint = world.brains[mac]?.hint { failures.append("\(mac) shows the hint \"\(hint)\"") }
            if world.brains[mac]?.openPrompt != nil { failures.append("\(mac) has a sheet open") }
        }
        return failures
    }

    /// Two further rounds of delivery and polling open no sheet, show no hint and write nothing, on any Mac.
    static func quiet(_ world: SimWorld) -> [String] {
        let writes = world.writeLog.count
        let prompts = promptCount(world)
        for _ in 0..<2 { settle(world) }
        var failures = silent(world)
        if world.writeLog.count != writes {
            let first = world.writeLog[writes]
            failures.append("\(first.mac) wrote \(first.path) in a round with no change (\(world.writeLog.count - writes) writes)")
        }
        if promptCount(world) != prompts { failures.append("\(promptCount(world) - prompts) sheets opened in a round with no change") }
        return failures
    }

    // MARK: Reading a world

    /// The value of a unit on a Mac.
    static func value(_ world: SimWorld, _ mac: SimMacName, _ unit: String) -> SimValue? {
        SimUnits.value(of: unit, in: world.defaults(of: mac))
    }

    /// A Mac's arrangement of the macOS version its generation names: the entry of the application the scenarios move on
    /// macOS 27, the entry `ItemSections/Visible` on macOS 26.
    static func arrangement(_ world: SimWorld, _ mac: SimMacName, generation: Int) -> SimValue? {
        value(world, mac, generation == 27 ? layoutA : sectionsEntry)
    }

    /// The units the sheets of a Mac have shown so far, in order.
    static func shownUnits(_ world: SimWorld, _ mac: SimMacName? = nil) -> [String] {
        world.allSteps.flatMap(\.prompts).filter { mac == nil || $0.mac == mac }.flatMap { $0.prompt.shown.map(\.unit) }
    }

    /// The sheets that asked about an arrangement (`ItemSections`, `l27/*`, `prof/*`).
    static func layoutQuestions(_ world: SimWorld) -> [String] {
        shownUnits(world).filter { $0.hasPrefix("ItemSections") || $0.hasPrefix("l27/") || $0.hasPrefix("prof/") }
    }

    /// The writes a Mac made to the folder, in order.
    static func writes(_ world: SimWorld, by mac: SimMacName, path: String? = nil) -> [SimWriteRecord] {
        world.writeLog.filter { $0.mac == mac && (path == nil || $0.path == path) }
    }

    /// The path of a redesigned Mac's own device file.
    static func ownPath(_ world: SimWorld, _ mac: SimMacName) -> String? {
        SimMacRedesignProbe.id(of: world, mac).map { SimFolderIO.directory + "/\($0).plist" }
    }

    /// What a redesigned Mac's own file holds for a unit: the live entries of the last write.
    static func publishedEntries(_ world: SimWorld, _ mac: SimMacName, _ unit: String) -> [SyncEntry] {
        guard let key = SimEngineUnits.key(ofUnit: unit), let own = SimMacRedesignProbe.id(of: world, mac),
              let write = writes(world, by: mac, path: SimFolderIO.directory + "/\(own).plist").last,
              case .success(let contents) = SyncDeviceFile.decode(write.data, fileName: "\(own).plist")
        else { return [] }
        return contents.replica.live(key)
    }

    /// The state in a redesigned Mac's Sigma blob.
    static func state(_ world: SimWorld, _ mac: SimMacName) -> SyncState? {
        SimMacRedesignProbe.state(of: world, mac)
    }

    /// The values of the live entries of a unit in a redesigned Mac's replica (more than one: waiting siblings).
    static func live(_ world: SimWorld, _ mac: SimMacName, _ unit: String) -> [SimValue] {
        guard let key = SimEngineUnits.key(ofUnit: unit), let state = state(world, mac) else { return [] }
        return state.replica.live(key).compactMap(\.value).compactMap { SimValue(sync: $0) }
    }

    /// Whether the sync folder could be used at a redesigned Mac's last read.
    static func availability(_ world: SimWorld, _ mac: SimMacName) -> SyncFolderAvailability? {
        (world.brains[mac] as? SimMacRedesign)?.folderAvailability
    }

    /// The launch hooks a Mac ran, in order.
    static func launchHooks(_ world: SimWorld, _ mac: SimMacName) -> [SimHookRecord] {
        world.allSteps.flatMap(\.hooks).filter { $0.mac == mac && $0.name == .launch }
    }

    /// The status lines a redesigned Mac shows.
    static func lines(_ world: SimWorld, _ mac: SimMacName) -> [SyncStatusLine] {
        (world.brains[mac] as? SimMacRedesign)?.statusLines ?? []
    }

    // MARK: The beta1 boundary

    /// What every scenario with a real 0.0.7-beta1 peer asserts of the redesigned Macs (analysis section 4.8): they
    /// never write the legacy file, a status line (the old-group line) is the only trace of the peer, they show no
    /// hint (unless the scenario has changes between redesigned Macs that wait, `hints`), and they opened `sheets` sheets,
    /// which the scenario names (`nil` leaves the count to the scenario).
    static func boundary(_ world: SimWorld, redesigned: [SimMacName], sheets: Int? = 0, hints: Bool = false) -> [String] {
        var failures: [String] = []
        for mac in redesigned {
            // Only what the redesigned build wrote counts: a Mac that was on beta1 before its update wrote the file as beta1.
            for write in writes(world, by: mac, path: SimFolderIO.legacyPath) where write.brainKind == .redesign || write.brainKind == .redesignSkew {
                failures.append("\(mac) wrote the legacy file \(write.path)")
            }
            let extra = lines(world, mac).filter { $0 != .olderHolzBar }
            if !extra.isEmpty { failures.append("\(mac) shows \(extra) beyond the old-group line") }
            if !hints, let hint = world.brains[mac]?.hint { failures.append("\(mac) shows the hint \"\(hint)\" because of the old peer") }
        }
        let opened = world.allSteps.flatMap(\.prompts).filter { redesigned.contains($0.mac) }.count
        if let sheets, opened != sheets { failures.append("\(opened) sheets on the redesigned Macs, expected \(sheets)") }
        return failures
    }

    /// The legacy file's bytes in the folder as one Mac sees them, if there is one.
    static func legacyBytes(_ world: SimWorld, as mac: SimMacName) -> Data? {
        if case .present(let data)? = world.replica(of: mac).entries[SimFolderIO.legacyPath] { return data }
        return nil
    }

    // MARK: The two forms of a scope scenario

    /// A scenario that Appendix B classes as SCOPE runs twice, as `<id>/26` on generation-26 Macs (the arrangement keys
    /// asserted untouched and unprompted) and as `<id>/27` on generation-27 Macs in its arrangement form (decisions
    /// D-04 and D-11).
    static func forms(
        of id: String,
        title: String,
        source: CatalogueSource = .a1,
        run: @escaping @Sendable (_ generation: Int) -> SimScenarioResult
    ) -> [CatalogueScenario] {
        [26, 27].map { generation in
            CatalogueScenario(id: "\(id)/\(generation)", title: "\(title) (generation \(generation))", source: source, kind: .scope) {
                run(generation)
            }
        }
    }

    // MARK: Texts and failures

    /// The A1 text of an id; a form id (`S-15/27`) has the text of its base.
    static func a1Text(id: String) -> CatalogueText? {
        let base = id.split(separator: "/").first.map(String.init) ?? id
        return a1Texts[base]
    }

    /// Every table of A1 texts; plans 28-11 and 28-12 add theirs here.
    static let a1Tables: [[String: CatalogueText]] = [
        CatalogueG1Joining.texts,
        CatalogueG2Infrastructure.texts,
        CatalogueG3Generations.texts,
        CatalogueG4BetaPeers.texts,
        CatalogueG5Clocks.texts,
        CatalogueG6FileFaults.texts,
    ]

    static let a1Texts: [String: CatalogueText] = a1Tables.reduce(into: [:]) { merged, table in merged.merge(table) { first, _ in first } }

    /// The failure message of a scenario: its A1 Setup, Steps, Wrong and Must, then what failed.
    static func message(_ scenario: CatalogueScenario, _ result: SimScenarioResult) -> String {
        var lines = ["\(scenario.id) (\(scenario.kind.rawValue), \(scenario.source.rawValue)): \(scenario.title)"]
        if let text = a1Text(id: scenario.id) {
            lines += ["Setup: \(text.setup)", "Steps: \(text.steps)", "Wrong: \(text.wrong)", "Must: \(text.must)"]
        }
        lines.append("Failed:")
        lines += result.failures.map { "  - \($0)" }
        return lines.joined(separator: "\n")
    }

    /// Runs a scenario and records one issue with its A1 text when anything failed.
    static func check(_ scenario: CatalogueScenario, sourceLocation: SourceLocation = #_sourceLocation) {
        let result = scenario.run()
        if !result.passed {
            Issue.record(Comment(rawValue: message(scenario, result)), sourceLocation: sourceLocation)
        }
    }
}

// MARK: - DSL additions

extension SimScenario {
    /// Delivers everything, lets the poll run and delivers again.
    func settle() -> SimScenario { perform("settle") { Catalogue.settle($0); return [] } }

    /// Restarts every running Mac until a round changes nothing.
    func relaunchAll() -> SimScenario { perform("relaunch") { Catalogue.relaunchUntilQuiet($0); return [] } }

    /// Two further rounds open no sheet, show no hint and write nothing.
    func expectQuiet() -> SimScenario { perform("quiet") { Catalogue.quiet($0) } }

    /// No Mac shows a hint or has a sheet open now.
    func expectSilent() -> SimScenario { perform("silent") { Catalogue.silent($0) } }

    /// The Mac holds the user's value number `k` of the unit.
    func expectUser(_ mac: SimMacName, _ unit: String, _ k: Int) -> SimScenario {
        expectValue(mac, unit, Catalogue.user(k, unit))
    }

    /// A free expectation over the world that returns the text of its failure.
    func expect(_ label: String, _ body: @escaping (SimWorld) -> String?) -> SimScenario {
        perform(label) { world in body(world).map { [$0] } ?? [] }
    }

    /// The Mac's value of a unit has the user's token number `k` at some depth (a dictionary entry of an arrangement).
    func expectToken(_ mac: SimMacName, _ unit: String, contains token: String) -> SimScenario {
        expect("\(mac) \(unit)") { world in
            let held = Catalogue.value(world, mac, unit)
            return held?.tokens.contains(token) == true ? nil : "\(mac) holds \(held?.canonical ?? "nothing") at \(unit), expected the token \(token)"
        }
    }

    /// No sheet asked about an arrangement.
    func expectNoLayoutQuestion() -> SimScenario {
        expect("no arrangement question") { world in
            let asked = Catalogue.layoutQuestions(world)
            return asked.isEmpty ? nil : "a sheet asked about \(asked)"
        }
    }

    /// Remembers a Mac's arrangement now.
    func noteArrangement(_ mac: SimMacName, generation: Int, in box: CatalogueBox<SimValue?>) -> SimScenario {
        perform("note the arrangement of \(mac)") { world in
            box.value = Catalogue.arrangement(world, mac, generation: generation)
            return []
        }
    }

    /// The Mac's arrangement is what `box` holds (a value noted earlier, or the one a scenario knows).
    func expectArrangement(_ mac: SimMacName, generation: Int, is box: CatalogueBox<SimValue?>) -> SimScenario {
        expect("\(mac) keeps its arrangement") { world in
            let held = Catalogue.arrangement(world, mac, generation: generation)
            return held == box.value ? nil : "\(mac) holds \(held?.canonical ?? "nothing"), expected \(box.value?.canonical ?? "nothing")"
        }
    }

    /// The beta1 boundary holds for the redesigned Macs; `sheets` is how many sheets they opened.
    func expectBoundary(redesigned: [SimMacName], sheets: Int? = 0, hints: Bool = false) -> SimScenario {
        perform("beta1 boundary") { Catalogue.boundary($0, redesigned: redesigned, sheets: sheets, hints: hints) }
    }

    /// The Mac shows the old-group status line, or not.
    func expectOlderLine(_ mac: SimMacName, present: Bool) -> SimScenario {
        expect("\(mac) old-group line") { world in
            Catalogue.lines(world, mac).contains(.olderHolzBar) == present ? nil : "the old-group line is \(present ? "missing" : "shown") on \(mac)"
        }
    }

    /// The Mac's defaults hold exactly `value` at `key` (a whole key such as `ItemSections`).
    func expectKey(_ mac: SimMacName, _ key: String, _ value: SimValue?) -> SimScenario {
        expect("\(mac) \(key)") { world in
            world.defaults(of: mac)[key] == value ? nil : "\(mac) holds \(world.defaults(of: mac)[key]?.canonical ?? "nothing") at \(key), expected \(value?.canonical ?? "nothing")"
        }
    }
}

// MARK: - Provider events on a Mac's own file

/// A value a scenario step writes and a later step reads.
final class CatalogueBox<Value> {
    var value: Value

    init(_ value: Value) { self.value = value }
}

extension SimScenario {
    /// The provider events below name a file by its owner: the ID of a redesigned Mac is only known once it runs.
    private func providerEvent(_ label: String, _ owner: SimMacName, _ make: @escaping (String) -> SimProviderEvent) -> SimScenario {
        perform(label) { world in
            guard let path = Catalogue.ownPath(world, owner) else { return ["\(owner) has no device file yet"] }
            world.step(.provider(make(path)))
            return []
        }
    }

    /// The file of `owner` becomes a dataless placeholder on `mac` (Optimize Storage, Files On-Demand).
    func evictFile(of owner: SimMacName, on mac: SimMacName) -> SimScenario {
        providerEvent("evict the file of \(owner) on \(mac)", owner) { .evict(path: $0, mac: mac) }
    }

    /// The file of `owner` is deleted everywhere.
    func deleteFile(of owner: SimMacName) -> SimScenario {
        providerEvent("delete the file of \(owner)", owner) { .delete(path: $0) }
    }

    /// Another app puts bytes of `kind` where the file of `owner` is.
    func foreignFile(of owner: SimMacName, _ kind: SimForeignKind) -> SimScenario {
        providerEvent("put \(kind.rawValue) bytes over the file of \(owner)", owner) { .foreign(path: $0, kind: kind) }
    }

    /// Remembers how many times `owner` has written its file so far (the version a sync app could restore later).
    func markFile(of owner: SimMacName, in box: CatalogueBox<Int>) -> SimScenario {
        perform("mark the file of \(owner)") { world in
            guard let path = Catalogue.ownPath(world, owner) else { return ["\(owner) has no device file yet"] }
            box.value = Catalogue.writes(world, by: owner, path: path).count - 1
            return []
        }
    }

    /// Puts the file of `owner` back to the write that `box` marked, as a sync app restoring an old version would.
    func restoreFile(of owner: SimMacName, to box: CatalogueBox<Int>) -> SimScenario {
        perform("restore the file of \(owner)") { world in
            guard let path = Catalogue.ownPath(world, owner) else { return ["\(owner) has no device file yet"] }
            let writes = Catalogue.writes(world, by: owner, path: path)
            guard box.value >= 0, box.value < writes.count, let version = writes[box.value].version else {
                return ["no marked write of \(owner) to restore"]
            }
            world.step(.provider(.restore(path: path, version: version)))
            return []
        }
    }
}
