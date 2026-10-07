import Foundation

/// A trace setup that can be run again: the Macs, the provider, the seed and how brains are made.
struct SimMetaSetup {
    var seed: UInt64
    var preset: SimProviderPreset?
    var policy: SimFaultPolicy?
    var macs: [SimMacSpec]
    var brainFactory: SimWorld.BrainFactory

    init(
        seed: UInt64,
        preset: SimProviderPreset? = nil,
        policy: SimFaultPolicy? = nil,
        macs: [SimMacSpec],
        brainFactory: @escaping SimWorld.BrainFactory
    ) {
        self.seed = seed
        self.preset = preset
        self.policy = policy
        self.macs = macs
        self.brainFactory = brainFactory
    }
}

/// What a run decided, in a form two runs can be compared in: the prompts, the hints and open sheets after every
/// original event, the user tokens each Mac holds after every original event, and the user-state publications.
/// Automatic tokens are replaced by one word so that counters of automatic changes do not matter, and only tokens,
/// never counters or file bytes, are compared, which is the comparison "modulo counter renaming" of INV-F9.
struct SimTraceObservation: Equatable, Sendable {
    var prompts: [String] = []
    var decisions: [[String]] = []
    var states: [[String]] = []
    var publications: [String] = []
    var finalState: [String] = []
    var userChanges = 0
}

/// Metamorphic pairs (analysis section 5.4): the same trace under a change that must not matter.
enum SimMetamorphic {
    // MARK: Observation

    private static func userTokens(_ tokens: some Sequence<String>, in world: SimWorld) -> [String] {
        tokens.filter { world.groundTruth.origin(of: $0) != .automatic }.sorted()
    }

    private static func normalized(_ token: String?, in world: SimWorld) -> String {
        guard let token else { return "-" }
        return world.groundTruth.origin(of: token) == .automatic ? "auto" : token
    }

    static func observe(
        _ setup: SimMetaSetup,
        _ events: [SimEvent],
        insertions: [Int: [SimEvent]] = [:],
        tail: [SimEvent] = [],
        macs: [SimMacSpec]? = nil,
        policy: SimFaultPolicy? = nil,
        seed: UInt64? = nil
    ) -> (observation: SimTraceObservation, world: SimWorld) {
        let world = SimWorld(
            seed: seed ?? setup.seed, macs: macs ?? setup.macs, preset: setup.preset, policy: policy ?? setup.policy,
            brainFactory: setup.brainFactory
        )
        var observation = SimTraceObservation()
        for (index, event) in events.enumerated() {
            world.run(insertions[index] ?? [])
            world.step(event)
            var decisions: [String] = []
            var states: [String] = []
            for mac in world.macs.keys.sorted() {
                let brain = world.brains[mac]!
                let prompt = brain.openPrompt.map { sheet in
                    sheet.shown.map { "\($0.unit):\(normalized($0.local, in: world)):\(normalized($0.folder, in: world))" }.joined(separator: ",")
                }
                decisions.append("\(mac) hint=\(brain.hint ?? "-") sheet=\(prompt ?? "-")")
                states.append("\(mac) \(userTokens(SimUnits.tokens(in: world.macs[mac]!.defaults), in: world))")
            }
            observation.decisions.append(decisions)
            observation.states.append(states)
        }
        world.run(tail)
        for record in world.stepRecords.flatMap(\.prompts) {
            let units = record.prompt.shown.map {
                "\($0.unit):\(normalized($0.local, in: world)):\(normalized($0.folder, in: world))"
            }
            observation.prompts.append("\(record.mac) \(record.prompt.title) \(units.joined(separator: ","))")
        }
        for write in world.writeLog where write.version != nil {
            var tokens = Set<String>()
            for mac in world.brains.keys.sorted() { tokens.formUnion(world.brains[mac]!.heldTokens(inFile: write.path, data: write.data)) }
            let claimed = world.brains[write.mac]?.claimedPast(ofFile: write.path, data: write.data)
            observation.publications.append(
                "\(write.mac) \(write.path) \(userTokens(tokens, in: world)) claimed=\(claimed.map { userTokens($0, in: world).description } ?? "-")"
            )
        }
        observation.finalState = world.macs.keys.sorted().map { "\($0) \(userTokens(SimUnits.tokens(in: world.macs[$0]!.defaults), in: world))" }
        observation.userChanges = world.groundTruth.changes.filter { $0.kind == .user }.count
        return (observation, world)
    }

    private static func violation(
        _ id: SimInvariantID, _ setup: SimMetaSetup, _ events: [SimEvent], _ description: String
    ) -> SimViolation {
        SimViolation(id: id, seed: setup.seed, stepIndex: events.count, description: description, trace: events.map(\.canonical))
    }

    private static func firstDifference(_ left: [String], _ right: [String]) -> String? {
        for (index, pair) in zip(left, right).enumerated() where pair.0 != pair.1 {
            return "#\(index): \(pair.0)  versus  \(pair.1)"
        }
        return left.count == right.count ? nil : "\(left.count) entries versus \(right.count)"
    }

    private static func firstDifference(_ left: [[String]], _ right: [[String]]) -> String? {
        for (index, pair) in zip(left, right).enumerated() where pair.0 != pair.1 {
            return "after event \(index): \(pair.0)  versus  \(pair.1)"
        }
        return left.count == right.count ? nil : "\(left.count) entries versus \(right.count)"
    }

    // MARK: INV-A1

    /// The same trace with and without automatic events gives the same prompts, hints and user-state publications.
    static func automaticEventsInvisible(
        _ setup: SimMetaSetup, _ events: [SimEvent], insertionSeed: UInt64 = 1
    ) -> [SimViolation] {
        var random = SimRandom(seed: insertionSeed).fork("automatic-insertions")
        let names = setup.macs.map(\.name)
        var insertions: [Int: [SimEvent]] = [:]
        for index in events.indices where random.chance(0.35) {
            let mac = random.pick(names)
            switch random.int(in: 0...2) {
            // An automatic placement never overwrites an entry backed by the user's intent, so it gets a unit of its own.
            case 0: insertions[index] = [.autoPlace(mac: mac, unit: "RevealRules/auto\(index)")]
            case 1: insertions[index] = [.learn(mac: mac, key: "KnownItemTags")]
            default: insertions[index] = [.setFlag(mac: mac, key: "HasImportedIceSettings")]
            }
        }
        let plain = observe(setup, events).observation
        let noisy = observe(setup, events, insertions: insertions).observation
        var found: [SimViolation] = []
        if let difference = firstDifference(plain.prompts, noisy.prompts) {
            found.append(violation("INV-A1", setup, events, "automatic events changed the prompts: \(difference)"))
        }
        if let difference = firstDifference(plain.decisions, noisy.decisions) {
            found.append(violation("INV-A1", setup, events, "automatic events changed a hint or sheet: \(difference)"))
        }
        if let difference = firstDifference(plain.publications, noisy.publications) {
            found.append(violation("INV-A1", setup, events, "automatic events changed a user-state publication: \(difference)"))
        }
        return found
    }

    // MARK: INV-F9

    /// The same trace with randomized clock offsets and clock steps gives the same decisions and publications, compared
    /// modulo counter renaming.
    static func clockIndependence(_ setup: SimMetaSetup, _ events: [SimEvent], clockSeed: UInt64 = 1) -> [SimViolation] {
        var random = SimRandom(seed: clockSeed).fork("clocks")
        var skewed = setup.macs
        for index in skewed.indices {
            skewed[index].clockOffsetMilliseconds = Int64(random.int(in: -3...3)) * 3_600_000
        }
        var insertions: [Int: [SimEvent]] = [:]
        for index in events.indices where random.chance(0.25) {
            insertions[index] = [.clockStep(mac: random.pick(setup.macs.map(\.name)), milliseconds: Int64(random.int(in: -3...3)) * 3_600_000)]
        }
        let plain = observe(setup, events).observation
        let shifted = observe(setup, events, insertions: insertions, macs: skewed).observation
        var found: [SimViolation] = []
        if let difference = firstDifference(plain.decisions, shifted.decisions) {
            found.append(violation("INV-F9", setup, events, "clock offsets changed a hint or sheet: \(difference)"))
        }
        if let difference = firstDifference(plain.states, shifted.states) {
            found.append(violation("INV-F9", setup, events, "clock offsets changed what a Mac holds: \(difference)"))
        }
        if let difference = firstDifference(plain.prompts, shifted.prompts) {
            found.append(violation("INV-F9", setup, events, "clock offsets changed the prompts: \(difference)"))
        }
        if let difference = firstDifference(plain.publications, shifted.publications) {
            found.append(violation("INV-F9", setup, events, "clock offsets changed a publication: \(difference)"))
        }
        return found
    }

    // MARK: INV-F2, INV-F3

    private static func settledState(_ setup: SimMetaSetup, _ events: [SimEvent], policy: SimFaultPolicy, seed: UInt64) -> [String] {
        let run = observe(setup, events, policy: policy, seed: seed)
        var config = SimDrainConfig()
        config.answers = .use
        config.fresh = nil
        SimDrain.run(run.world, config: config)
        return run.world.macs.keys.sorted().map {
            "\($0) \(userTokens(SimUnits.tokens(in: run.world.macs[$0]!.defaults), in: run.world))"
        }
    }

    /// Permuted, duplicated and coalesced deliveries of the same writes give the same final state. The baseline is an
    /// ideal provider; the variants reorder and coalesce (INV-F2) and duplicate (INV-F3) under other seeds.
    static func deliveryIndependence(_ setup: SimMetaSetup, _ events: [SimEvent], variantSeeds: [UInt64] = [11, 12, 13]) -> [SimViolation] {
        let baseline = settledState(setup, events, policy: .ideal, seed: setup.seed)
        var found: [SimViolation] = []
        for seed in variantSeeds {
            var permuted = SimFaultPolicy(medianDelayMilliseconds: 4_000, coalesceProbability: 0.5)
            permuted.signalsFolderChanges = true
            if let difference = firstDifference(baseline, settledState(setup, events, policy: permuted, seed: seed)) {
                found.append(violation("INV-F2", setup, events, "another delivery order (seed \(seed)) ended differently: \(difference)"))
            }
            var duplicated = SimFaultPolicy(medianDelayMilliseconds: 2_000, coalesceProbability: 1, duplicateProbability: 0.7)
            duplicated.signalsFolderChanges = true
            if let difference = firstDifference(baseline, settledState(setup, events, policy: duplicated, seed: seed)) {
                found.append(violation("INV-F3", setup, events, "duplicate deliveries (seed \(seed)) ended differently: \(difference)"))
            }
        }
        return found
    }

    // MARK: INV-A5

    /// Launches with no user events, of Macs on another build or after a beta2 run, mint nothing: they change no other
    /// Mac's publications or decisions and publish no token that no user ever made.
    static func launchesMintNothing(
        _ setup: SimMetaSetup, _ events: [SimEvent], launching extras: [SimMacName], insertionSeed: UInt64 = 1
    ) -> [SimViolation] {
        var random = SimRandom(seed: insertionSeed).fork("dot-free-launches")
        var insertions: [Int: [SimEvent]] = [:]
        for index in events.indices where random.chance(0.4) {
            let extra = random.pick(extras)
            insertions[index] = [.launch(mac: extra), .restartApp(mac: extra)]
        }
        let plain = observe(setup, events)
        let launched = observe(setup, events, insertions: insertions)
        var found: [SimViolation] = []
        let originals = Set(setup.macs.map(\.name)).subtracting(extras)
        func filtered(_ lines: [String]) -> [String] { lines.filter { line in originals.contains { line.hasPrefix("\($0) ") } } }
        if let difference = firstDifference(filtered(plain.observation.publications), filtered(launched.observation.publications)) {
            found.append(violation("INV-A5", setup, events, "a dot-free launch changed another Mac's publication: \(difference)"))
        }
        if launched.observation.userChanges != plain.observation.userChanges {
            found.append(violation("INV-A5", setup, events, "a launch without user events minted a user change"))
        }
        let truth = launched.world.groundTruth
        for write in launched.world.writeLog where extras.contains(write.mac) && write.version != nil {
            var tokens = Set<String>()
            for mac in launched.world.brains.keys.sorted() {
                tokens.formUnion(launched.world.brains[mac]!.heldTokens(inFile: write.path, data: write.data))
            }
            for token in tokens.sorted() where truth.origin(of: token) == .automatic || (truth.origin(of: token) == .user && truth.change(forToken: token) == nil) {
                found.append(violation("INV-A5", setup, events, "Mac \(write.mac) published \(token), which no user made, after launching with no user events"))
            }
        }
        return found
    }
}
