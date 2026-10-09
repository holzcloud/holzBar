import Foundation
import Testing

/// A small engine that really converges, so the drain and the metamorphic pairs have something to pass: every Mac
/// publishes its own user units in `holzBar/Macs/<mac>.plist`, applies the unit value with the highest token number
/// from every other Mac's file and ignores automatic values. Each flaw breaks it in one specific way.
struct SimConvergentTestBrain: SimSyncBrain {
    enum Flaw: Sendable {
        case none
        /// Never applies anything from the folder (the Macs diverge).
        case ignoresOthers
        /// Rewrites its file at every launch even when nothing changed.
        case writesAtEveryLaunch
        /// Opens a sheet at every launch.
        case promptsAtEveryLaunch
        /// Shows a hint that never goes away.
        case alwaysHints
        /// Publishes on automatic changes too.
        case publishesAutomatic
        /// Writes a token no user made at launch.
        case mintsAtLaunch
    }

    var flaw = Flaw.none
    var kind: SimMacVersion = .redesign
    private var ingested: [String: Int] = [:]
    private var sheet: SimPrompt?
    private var promptCounter = 0
    private var forceWrite = false

    init(flaw: Flaw = .none, kind: SimMacVersion = .redesign) {
        self.flaw = flaw
        self.kind = kind
    }

    static let directory = "holzBar/Macs"

    private func ownPath(_ context: SimMacContext) -> String { "\(Self.directory)/\(context.mac.name).plist" }

    private static func rank(_ value: SimValue?) -> Int {
        var best = -1
        for token in value?.tokens ?? [] {
            if case .user(let k, _)? = SimValue.origin(ofToken: token) { best = max(best, k) }
        }
        return best
    }

    private func publishedUnits(_ context: SimMacContext) -> [String: SimValue] {
        var units: [String: SimValue] = [:]
        for (unit, value) in SimUnits.units(of: context.defaults) where SimLocalKeys.isSyncedUnit(unit, generation: context.environment.generation) {
            let automatic = value.tokens.contains { SimValue.origin(ofToken: $0).map { if case .automatic = $0 { true } else { false } } ?? false }
            if automatic, flaw != .publishesAutomatic { continue }
            units[unit] = value
        }
        return units
    }

    private mutating func publish(_ context: inout SimMacContext) {
        guard context.enabled, context.folderID != nil else { return }
        var units = publishedUnits(context)
        if flaw == .mintsAtLaunch, forceWrite { units["Minted"] = .string("u99@Minted") }
        let file: [String: Any] = ["writer": context.mac.name, "units": units.mapValues(\.propertyList)]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0) else { return }
        let path = ownPath(context)
        let result = context.read(path, maximumBytes: 1 << 20)
        if case .data(let existing, _) = result, !forceWrite,
           SimDigest.canonicalRendering(of: existing) == SimDigest.canonicalRendering(of: data) {
            return
        }
        if result == .notLocal { context.requestDownload(path); return }
        if case .data = result {} else if result != .absent { return }
        _ = context.write(path, data)
    }

    private mutating func sync(_ context: inout SimMacContext) {
        guard context.enabled, context.folderID != nil, flaw != .ignoresOthers else { return }
        guard case .names(let names) = context.list(Self.directory) else { return }
        let own = ownPath(context)
        for name in names {
            let path = "\(Self.directory)/\(name)"
            guard path != own else { continue }
            let result = context.read(path, maximumBytes: 1 << 20)
            if result == .notLocal { context.requestDownload(path) }
            guard case .data(let data, let version) = result,
                  let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let file = object as? [String: Any], let raw = file["units"] as? [String: Any]
            else { continue }
            for unit in raw.keys.sorted() {
                guard let value = SimValue(propertyList: raw[unit]!),
                      SimLocalKeys.isSyncedUnit(unit, generation: context.environment.generation),
                      context.environment.generation == 27 || SimUnits.generationScope(unit) != 27
                else { continue }
                if Self.rank(value) > Self.rank(SimUnits.value(of: unit, in: context.defaults)) {
                    SimUnits.set(unit, to: value, in: &context.defaults)
                }
            }
            if ingested[path] != version {
                ingested[path] = version
                context.reportIngest(version: version)
            }
        }
    }

    mutating func launch(_ context: inout SimMacContext) {
        sync(&context)
        forceWrite = flaw == .writesAtEveryLaunch || flaw == .mintsAtLaunch
        publish(&context)
        forceWrite = false
        if flaw == .promptsAtEveryLaunch {
            promptCounter += 1
            let open = SimPrompt(id: promptCounter, title: "Settings differ", shown: [])
            sheet = open
            context.reportPrompt(open)
        }
    }

    mutating func quit(_ context: inout SimMacContext) { sheet = nil }
    mutating func processDied() { sheet = nil }

    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        if origin == .automatic, flaw != .publishesAutomatic { return }
        forceWrite = origin == .automatic
        publish(&context)
        forceWrite = false
    }

    mutating func folderSignal(_ context: inout SimMacContext) {
        sync(&context)
        publish(&context)
    }

    mutating func timerFired(tag: String, _ context: inout SimMacContext) {}

    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        switch command {
        case .turnOn(let folder), .changeFolder(let folder):
            context.enabled = true
            context.folderID = folder
            sync(&context)
            publish(&context)
        case .turnOff: context.enabled = false
        case .restart: context.requestRelaunch()
        case .importFile: publish(&context)
        case .answer: sheet = nil
        }
    }

    var hint: String? { flaw == .alwaysHints ? "Settings differ" : nil }
    var openPrompt: SimPrompt? { sheet }

    func heldTokens(inFile path: String, data: Data) -> Set<String> {
        guard path.hasPrefix(Self.directory),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let file = object as? [String: Any], let raw = file["units"] as? [String: Any]
        else { return [] }
        var tokens = Set<String>()
        for value in raw.values { tokens.formUnion(SimValue(propertyList: value)?.tokens ?? []) }
        return tokens
    }
}

/// The harness itself: budget, generator, runner, drain, metamorphic pairs, scenario DSL and the shared-file control.
@Suite("SimHarness")
struct SimHarnessTests {
    static func convergent(_ flaw: SimConvergentTestBrain.Flaw = .none) -> SimWorld.BrainFactory {
        { version, _ in SimConvergentTestBrain(flaw: flaw, kind: version == .redesignSkew ? .redesignSkew : .redesign) }
    }

    static func twoMacs(generation: Int = 26) -> [SimMacSpec] {
        [SimMacSpec(.A, .redesign, generation: generation, running: true), SimMacSpec(.B, .redesign, generation: generation, running: true)]
    }

    /// Edits of different units on both Macs with time between them, so nothing is concurrent on one unit.
    static let calmTrace: [SimEvent] = [
        .userEdit(mac: .A, unit: "ShowOnHover"), .advance(milliseconds: 2_000),
        .userEdit(mac: .B, unit: "UseIceBar"), .advance(milliseconds: 2_000),
        .userEdit(mac: .A, unit: "RehideInterval"), .advance(milliseconds: 5_000),
        .restartApp(mac: .B), .userEdit(mac: .B, unit: "Hotkeys/toggle"), .advance(milliseconds: 5_000),
    ]

    static func drained(
        flaw: SimConvergentTestBrain.Flaw = .none,
        trace: [SimEvent] = calmTrace,
        preset: SimProviderPreset? = nil,
        seed: UInt64 = 1,
        config: SimDrainConfig = SimDrainConfig()
    ) -> (world: SimWorld, facts: SimDrainFacts) {
        let world = SimWorld(seed: seed, macs: twoMacs(), preset: preset, brainFactory: convergent(flaw))
        world.run(trace)
        let facts = SimDrain.run(world, config: config)
        return (world, facts)
    }

    static func ids(_ world: SimWorld) -> Set<SimInvariantID> { Set(world.oracleViolations.map(\.id)) }

    // MARK: Budget

    @Test("The budget reads its four variables and falls back to CI defaults")
    func budget() {
        #expect(SimBudget.read(from: [:]) == SimBudget.ci)
        let custom = SimBudget.read(from: [
            "SYNC_SIM_SEEDS": "7", "SYNC_SIM_STEPS": "300", "SYNC_SIM_DEPTH": "6", "SYNC_FUZZ_INPUTS": "1000000",
        ])
        #expect(custom == SimBudget(seeds: 7, steps: 300, depth: 6, fuzzInputs: 1_000_000))
        #expect(SimBudget.read(from: ["SYNC_SIM_SEEDS": "many"]).seeds == SimBudget.ci.seeds)
        #expect(SimBudget.ci.seeds <= 100 && SimBudget.ci.steps <= 200)
    }

    // MARK: Generator

    @Test("The generator is reproducible, differs by seed and follows the preset's faults")
    func generator() {
        let macs = [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, generation: 27, running: true)]
        let config = SimGenerator.Config(macs: macs, preset: .hostile, steps: 300)
        let first = SimGenerator.events(seed: 5, config)
        #expect(first == SimGenerator.events(seed: 5, config))
        #expect(first != SimGenerator.events(seed: 6, config))
        #expect(first.count == 300)
        func isProvider(_ event: SimEvent) -> Bool { if case .provider = event { true } else { false } }
        #expect(first.contains(where: isProvider))
        let calm = SimGenerator.events(seed: 5, SimGenerator.Config(macs: macs, preset: nil, steps: 300))
        #expect(!calm.contains(where: isProvider))
        // macOS 27 events only target generation 27 Macs, and the 26 Mac gets no layout moves.
        for case .moveApp27(let mac, _, _) in first { #expect(mac == SimMacName.B) }
        #expect(first.contains { if case .moveApp27 = $0 { true } else { false } })
    }

    @Test("In drain mode the generator draws no user, identity, clock or fault events")
    func quiescentGenerator() {
        let macs = Self.twoMacs()
        let config = SimGenerator.Config(macs: macs, preset: .hostile, steps: 400).quiescent()
        for event in SimGenerator.events(seed: 9, config) {
            switch event {
            case .userEdit, .userDelete, .userImport, .setHotkey, .chooseItemIcon, .oversizeIcon, .moveApp27, .applyProfile,
                 .saveProfile, .renameProfile, .deleteProfile, .turnOn, .turnOff, .changeFolder, .upgradeOS, .crash, .updateApp,
                 .clone, .copyAccount, .restorePrefs, .restoreSigma, .restoreHome, .sigmaLost, .reinstall, .clockStep, .provider:
                Issue.record("\(event.canonical) is not allowed after T0")
            default:
                break
            }
        }
    }

    // MARK: Runner

    @Test("The runner replays a seed exactly and the exhaustive mode prunes visited states")
    func runner() {
        let macs = Self.twoMacs()
        func random(_ seed: UInt64) -> SimRunResult {
            SimRunner.run(seed: seed, preset: .iCloud, macs: macs, brainFactory: Self.convergent(), mode: .random(steps: 40))
        }
        #expect(random(3).traceHash == random(3).traceHash)
        #expect(random(3).traceHash != random(4).traceHash)
        #expect(random(3).events.count == 40)

        let alphabet: [SimEvent] = [
            .userEdit(mac: .A, unit: "ShowOnHover"), .userEdit(mac: .B, unit: "UseIceBar"), .advance(milliseconds: 1_000),
            .restartApp(mac: .A),
        ]
        let result = SimRunner.run(
            seed: 1, preset: nil, macs: macs, brainFactory: Self.convergent(), mode: .exhaustive(depth: 3, alphabet: alphabet),
            oracles: SimOracleSet.safety.only(["INV-S6", "INV-N1"])
        )
        #expect(result.violations.isEmpty)
        #expect(result.runs > 0)
        // Some sequences reach states another sequence reached already, so there are fewer states than runs.
        #expect(result.visitedStates < result.runs)
    }

    // MARK: Drain and liveness

    @Test("A converging engine passes the drain: agreement, quiet relaunches, bounded questions, progress and a fresh Mac")
    func drainPasses() {
        for preset in [nil, SimProviderPreset.iCloud] {
            for seed in UInt64(1)...6 {
                let run = Self.drained(preset: preset, seed: seed)
                #expect(run.facts.quiescent, "seed \(seed) did not become quiet")
                #expect(run.facts.freshChecked)
                #expect(run.world.oracleViolations.isEmpty, "seed \(seed) \(preset?.rawValue ?? "ideal"): \(run.world.oracleViolations.map { "\($0.id) \($0.description)" })")
            }
        }
        let run = Self.drained()
        #expect(run.world.defaults(of: .A)["ShowOnHover"] == run.world.defaults(of: .B)["ShowOnHover"])
        #expect(run.world.defaults(of: "Z")["Hotkeys/toggle"] == nil, "the unit is entry-granular: the key holds a dictionary")
        #expect(SimUnits.value(of: "Hotkeys/toggle", in: run.world.defaults(of: "Z")) == SimUnits.value(of: "Hotkeys/toggle", in: run.world.defaults(of: .A)))
    }

    @Test("INV-C1 and INV-C5 fire when the Macs never apply what the others published, and INV-C6 when a fresh Mac does not get it")
    func drainDivergence() {
        let run = Self.drained(flaw: .ignoresOthers)
        #expect(Self.ids(run.world).isSuperset(of: ["INV-C1", "INV-C5", "INV-C6"]))
    }

    @Test("INV-C2 fires when a Mac keeps writing at every launch")
    func drainWrites() {
        let run = Self.drained(flaw: .writesAtEveryLaunch)
        #expect(!run.facts.quiescent)
        #expect(Self.ids(run.world).contains("INV-C2"))
    }

    @Test("INV-C3 fires when questions never stop and INV-C4 when a hint never goes away")
    func drainQuestions() {
        #expect(Self.ids(Self.drained(flaw: .promptsAtEveryLaunch).world).contains("INV-C3"))
        let hinting = Self.drained(flaw: .alwaysHints)
        #expect(Self.ids(hinting.world).contains("INV-C4"))
        #expect(!hinting.facts.quiescent)
    }

    @Test("INV-P6 fires when a real conflict stays with no hint and no sheet")
    func drainConflict() {
        let trace: [SimEvent] = [
            .userEdit(mac: .A, unit: "ShowOnHover"), .userEdit(mac: .B, unit: "ShowOnHover"), .advance(milliseconds: 3_000),
        ]
        let silent = Self.drained(flaw: .ignoresOthers, trace: trace)
        #expect(Self.ids(silent.world).contains("INV-P6"))
        let hinted = Self.drained(flaw: .alwaysHints, trace: trace)
        // The Macs hold a conflict only until the engine applies; with a hint on screen the question is at least shown.
        #expect(!Self.ids(hinted.world).contains("INV-P6"))
    }

    @Test("The drain answers adversarially: Later at most the configured number of times")
    func drainAnswers() {
        var config = SimDrainConfig()
        config.maximumLaters = 1
        let run = Self.drained(flaw: .promptsAtEveryLaunch, config: config)
        #expect(run.facts.laters <= 1)
        var scripted = SimDrainConfig()
        scripted.answers = .script([.later, .keep, .use])
        let second = Self.drained(flaw: .promptsAtEveryLaunch, config: scripted)
        #expect(second.facts.laters >= 1)
    }

    // MARK: Metamorphic pairs

    static func metaSetup(_ factory: @escaping SimWorld.BrainFactory = convergent(), seed: UInt64 = 1, preset: SimProviderPreset? = .iCloud) -> SimMetaSetup {
        SimMetaSetup(seed: seed, preset: preset, macs: twoMacs(), brainFactory: factory)
    }

    @Test("INV-A1: a converging engine ignores automatic events and one that publishes on them is caught")
    func automaticEvents() {
        for seed in UInt64(1)...5 {
            let events = SimControlEngineTests.events(seed: seed, count: 30)
            let found = SimMetamorphic.automaticEventsInvisible(Self.metaSetup(seed: seed), events, insertionSeed: seed, generic: true)
            #expect(found.isEmpty, "seed \(seed): \(found.map(\.description))")
        }
        var caught = false
        for seed in UInt64(1)...20 where !caught {
            let events = SimControlEngineTests.events(seed: seed, count: 30)
            let found = SimMetamorphic.automaticEventsInvisible(Self.metaSetup(Self.convergent(.publishesAutomatic), seed: seed), events, insertionSeed: seed, generic: true)
            caught = found.contains { $0.id == "INV-A1" }
        }
        #expect(caught, "an engine that publishes automatic changes survived 20 seeds")
    }

    @Test("INV-F9: a converging engine is clock independent and last-writer-wins-by-clock is caught")
    func clockIndependence() {
        for seed in UInt64(1)...5 {
            let events = SimControlEngineTests.events(seed: seed, count: 30).filter { if case .clockStep = $0 { false } else { true } }
            #expect(SimMetamorphic.clockIndependence(Self.metaSetup(seed: seed), events, clockSeed: seed).isEmpty)
        }
        let lastWriter: SimWorld.BrainFactory = { _, _ in LastWriterWinsByClock() }
        var caught = false
        for seed in UInt64(1)...60 where !caught {
            let events = SimControlEngineTests.events(seed: seed, count: 30)
            caught = SimMetamorphic.clockIndependence(Self.metaSetup(lastWriter, seed: seed), events, clockSeed: seed).contains { $0.id == "INV-F9" }
        }
        #expect(caught, "LastWriterWinsByClock survived 60 seeds of the clock pair")
    }

    @Test("INV-F2 and INV-F3: delivery order, duplicates and coalescing do not change a converging engine's final state")
    func deliveryOrder() {
        for seed in UInt64(1)...4 {
            #expect(SimMetamorphic.deliveryIndependence(Self.metaSetup(seed: seed, preset: nil), Self.calmTrace, variantSeeds: [seed, seed + 10]).isEmpty)
        }
        // A Mac that keeps only what the last delivery said depends on the order.
        var caught = false
        let lastWriter: SimWorld.BrainFactory = { _, _ in LastWriterWinsByClock() }
        for seed in UInt64(1)...30 where !caught {
            let events = SimControlEngineTests.events(seed: seed, count: 24)
            let found = SimMetamorphic.deliveryIndependence(Self.metaSetup(lastWriter, seed: seed, preset: nil), events, variantSeeds: [seed])
            caught = found.contains { $0.id == "INV-F2" || $0.id == "INV-F3" }
        }
        #expect(caught, "an engine that depends on delivery order survived 30 seeds")
    }

    @Test("INV-A5: launches of other builds with no user events mint nothing; an engine that mints at launch is caught")
    func dotFreeLaunches() {
        let macs = [
            SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, running: true),
            SimMacSpec(.C, .redesignSkew, running: false),
        ]
        func setup(_ flaw: SimConvergentTestBrain.Flaw, seed: UInt64) -> SimMetaSetup {
            SimMetaSetup(seed: seed, preset: nil, macs: macs, brainFactory: { version, _ in
                SimConvergentTestBrain(flaw: version == .redesignSkew ? flaw : .none, kind: version == .redesignSkew ? .redesignSkew : .redesign)
            })
        }
        let events = Self.calmTrace
        for seed in UInt64(1)...4 {
            #expect(SimMetamorphic.launchesMintNothing(setup(.none, seed: seed), events, launching: [.C], insertionSeed: seed).isEmpty)
        }
        let minted = SimMetamorphic.launchesMintNothing(setup(.mintsAtLaunch, seed: 1), events, launching: [.C], insertionSeed: 1)
        #expect(minted.contains { $0.id == "INV-A5" })
    }

    // MARK: Scenario DSL

    @Test("A scenario with two beta1 Macs runs and its expectations pass or fail as stated")
    func scenario() {
        let passing = SimScenario("beta1 applies the other Mac's file", seed: 1)
            .macs(SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1))
            .edit(.A, "ShowOnHover")
            .advance(seconds: 6)
            .deliverAll()
            .expectFolderFiles([SimMacBeta1.filePath], mac: .B)
            .launch(.B)
            .expectValue(.B, "ShowOnHover", .string("u1@ShowOnHover"))
            .expectUnset(.B, "UseIceBar")
            .expectPrompts(count: 0, mac: .B)
            .expectHint(.A, present: true)
            .expectNoViolation()
            .run()
        #expect(passing.passed, "\(passing.failures)")

        let failing = SimScenario("a wrong expectation names the scenario", seed: 1)
            .macs(SimMacSpec(.A, .beta1, running: true))
            .edit(.A, "ShowOnHover")
            .expectUnset(.A, "ShowOnHover")
            .expectPrompts(count: 3)
            .run()
        #expect(failing.failures.count == 2)
        #expect(failing.failures.allSatisfy { $0.contains("a wrong expectation names the scenario") })

        let writes = SimScenario("no write since the checkpoint")
            .macs(SimMacSpec(.A, .beta1, running: true))
            .edit(.A, "ShowOnHover")
            .advance(seconds: 6)
            .checkpoint()
            .advance(seconds: 6)
            .expectNoWrite(.A)
            .edit(.A, "UseIceBar")
            .advance(seconds: 6)
            .expectNoWrite(.A)
            .run()
        #expect(writes.failures.count == 1)
    }

    @Test("The printed scenario replays: the builder calls it prints give the same trace")
    func printedScenarioReplays() {
        let events: [SimEvent] = [
            .userEdit(mac: .A, unit: "ShowOnHover"), .userDelete(mac: .B, unit: "UseIceBar"),
            .userEdit(mac: .A, unit: "RehideInterval", value: .int(3)), .advance(milliseconds: 6_000), .restartApp(mac: .A),
            .clockStep(mac: .B, milliseconds: 3_600_000), .answer(mac: .A, .later), .provider(.offline(mac: .B, forMilliseconds: 2_000)),
        ]
        let scenario = events.reduce(SimScenario("replay", seed: 4).macs([SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1, running: true)])) {
            $0.event($1)
        }
        #expect(scenario.events == events)
        let failure = SimFailure(
            name: "replay", seed: 4, preset: nil, macs: [SimMacSpec(.A, .beta1, running: true)], events: events,
            violation: SimViolation(id: "INV-S1", seed: 4, stepIndex: 1, description: "x", trace: [])
        )
        let text = SimScenarioPrinter.swiftTest(failure)
        for call in [".edit(.A, \"ShowOnHover\")", ".delete(.B, \"UseIceBar\")", ".edit(.A, \"RehideInterval\", value: .int(3))",
                     ".advance(seconds: 6)", ".restartApp(.A)", ".clockStep(.B, milliseconds: 3600000)",
                     ".answer(.A, .later)", ".provider(.offline(mac: .B, forMilliseconds: 2000))"] {
            #expect(text.contains(call), "missing \(call)")
        }
    }
}
