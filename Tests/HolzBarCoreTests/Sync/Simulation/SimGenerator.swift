import Foundation

// MARK: - Budget

/// How much the simulator runs. The numbers come from the environment (`SYNC_SIM_SEEDS`, `SYNC_SIM_STEPS`,
/// `SYNC_SIM_DEPTH`, `SYNC_FUZZ_INPUTS`) and fall back to small CI defaults, so a plain `swift test` stays fast and
/// the local gate before G1 (10,000 seeds per preset, full depth, a million fuzz inputs) is one `export` away.
struct SimBudget: Equatable, Sendable {
    var seeds: Int
    var steps: Int
    var depth: Int
    var fuzzInputs: Int
    /// The most runs one exhaustive family spends (`SYNC_SIM_RUNS`).
    var exhaustiveRuns = 1_500

    static let ci = SimBudget(seeds: 40, steps: 60, depth: 6, fuzzInputs: 10_000)

    /// Reads the budget from an environment (the process environment unless one is given).
    static func read(from environment: [String: String] = ProcessInfo.processInfo.environment) -> SimBudget {
        func value(_ name: String, _ fallback: Int) -> Int {
            environment[name].flatMap { Int($0) }.map { max($0, 0) } ?? fallback
        }
        return SimBudget(
            seeds: value("SYNC_SIM_SEEDS", ci.seeds),
            steps: value("SYNC_SIM_STEPS", ci.steps),
            depth: value("SYNC_SIM_DEPTH", ci.depth),
            fuzzInputs: value("SYNC_FUZZ_INPUTS", ci.fuzzInputs),
            exhaustiveRuns: value("SYNC_SIM_RUNS", ci.exhaustiveRuns)
        )
    }
}

// MARK: - Generator

/// Random events per provider preset, drawn from one seeded stream (analysis section 5.3). The generator knows the
/// Macs it draws for and the fault rates of the preset; it does not look at the world, so events on a Mac that is
/// not running are drawn too and are simply ignored by the world (as a user clicking in a quit app would be).
struct SimGenerator {
    struct Config: Sendable {
        var macs: [SimMacSpec]
        var preset: SimProviderPreset?
        var steps = 60
        var units = ["ShowOnHover", "UseIceBar", "RehideInterval", "Hotkeys/toggle", "ItemIcons/com.a", "RevealRules/r1"]
        var bundles = SimKeys.apps27
        var profiles = ["p1", "p2"]
        var folders = ["F1"]
        /// Builds a Mac can be updated to (empty: no `updateApp` events).
        var updateVersions: [SimMacVersion] = []
        var userEvents = true
        var automaticEvents = true
        var identityEvents = true
        /// Whether the identity events that destroy what a Mac's sync state knows (clone, copied account, restores of the preferences,
        /// of Sigma or of the home folder, a lost Sigma, a reinstall) are drawn. The OS upgrade stays with ``identityEvents``.
        var evidenceLoss = true
        var providerEvents = true
        var clockEvents = true
        var crashes = true

        init(macs: [SimMacSpec], preset: SimProviderPreset? = nil, steps: Int = 60) {
            self.macs = macs
            self.preset = preset
            self.steps = steps
        }

        /// From T0 on: no user events, no identity or clock events, no provider faults (A2 section 5.6, Q1 to Q3).
        /// Answers, launches, time and automatic events stay.
        func quiescent() -> Config {
            var copy = self
            copy.userEvents = false
            copy.identityEvents = false
            copy.providerEvents = false
            copy.clockEvents = false
            copy.crashes = false
            copy.updateVersions = []
            return copy
        }
    }

    private enum Kind: CaseIterable {
        case edit, delete, importFile, hotkey, itemIcon, oversize, turn, move27, profile
        case advance, launch, quit, restart, crash, answer
        case autoPlace, learn, flag, seed27, place27, upgrade
        case clock, identity, update
    }

    private static func weight(_ kind: Kind) -> Double {
        switch kind {
        case .edit: 18
        case .delete: 4
        case .importFile: 2
        case .hotkey: 3
        case .itemIcon: 2
        case .oversize: 0.3
        case .turn: 3
        case .move27: 4
        case .profile: 3
        case .advance: 22
        case .launch: 5
        case .quit: 3
        case .restart: 5
        case .crash: 1.5
        case .answer: 8
        case .autoPlace: 5
        case .learn: 3
        case .flag: 2
        case .seed27: 1
        case .place27: 1
        case .upgrade: 0.3
        case .clock: 3
        case .identity: 3
        case .update: 1
        }
    }

    private static func allowed(_ kind: Kind, _ config: Config) -> Bool {
        let has27 = config.macs.contains { $0.generation == 27 }
        switch kind {
        case .edit, .delete, .importFile, .hotkey, .itemIcon, .oversize, .turn: return config.userEvents
        case .move27, .profile: return config.userEvents && has27
        case .advance, .launch, .quit, .restart, .answer: return true
        case .crash: return config.crashes
        case .autoPlace, .learn, .flag: return config.automaticEvents
        case .seed27, .place27: return config.automaticEvents && has27
        case .upgrade: return config.identityEvents && config.macs.contains { $0.generation == 26 }
        case .clock: return config.clockEvents
        case .identity: return config.identityEvents && config.evidenceLoss && config.macs.count > 1
        case .update: return !config.updateVersions.isEmpty
        }
    }

    /// `steps` events for one seed.
    static func events(seed: UInt64, _ config: Config) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("generator")
        let names = config.macs.map(\.name)
        guard !names.isEmpty else { return [] }
        let kinds = Kind.allCases.filter { allowed($0, config) }
        let total = kinds.reduce(0.0) { $0 + weight($1) }
        let rates = config.providerEvents ? config.preset?.policy.rates : nil
        let faultTotal = rates.map(faultSum) ?? 0
        var events: [SimEvent] = []
        // The build each Mac runs, as the events so far leave it. holzBar offers only updates: a Mac that ran a redesigned build does
        // not go back to one that reports no intents and keeps no state (the changes it makes there no engine sees), so a world that
        // draws no event that destroys what a Mac's sync state knows draws updates to the same build or a later one only.
        var builds = Dictionary(uniqueKeysWithValues: config.macs.map { ($0.name, $0.version) })
        func rank(_ version: SimMacVersion) -> Int {
            switch version {
            case .beta1: 0
            case .beta2: 1
            case .redesign, .redesignSkew: 2
            }
        }
        for _ in 0..<config.steps {
            if let rates, faultTotal > 0, random.chance(min(faultTotal * 2, 0.5)) {
                events.append(fault(&random, rates: rates, names: names, config: config))
                continue
            }
            var pick = random.unit() * total
            var chosen = kinds[0]
            for kind in kinds {
                pick -= weight(kind)
                if pick <= 0 { chosen = kind; break }
            }
            var drawn = event(chosen, &random, names: names, config: config)
            if case .updateApp(let mac, let version) = drawn {
                if !config.evidenceLoss, let current = builds[mac], rank(version) < rank(current) {
                    drawn = .updateApp(mac: mac, version: current)
                } else {
                    builds[mac] = version
                }
            }
            // A copy of a Mac's preferences and sync state (Migration Assistant, a disk clone, another account) is taken from a
            // Mac whose last edit the engine has captured: the capture runs two seconds after an edit, and a copy taken inside
            // that window would carry an edit that its source publishes as its own again.
            switch drawn {
            case .clone, .copyAccount, .duplicateInstallation:
                events.append(.advance(milliseconds: 3_000))
            default:
                break
            }
            events.append(drawn)
        }
        return events
    }

    private static func faultSum(_ rates: SimFaultRates) -> Double {
        rates.restore + rates.delete + rates.deleteFolder + rates.evict + rates.exposePartial + rates.stall
            + rates.unmount + rates.foreign + rates.offline
    }

    private static func macs27(_ config: Config, _ random: inout SimRandom, _ names: [SimMacName]) -> SimMacName {
        let candidates = config.macs.filter { $0.generation == 27 }.map(\.name)
        return candidates.isEmpty ? random.pick(names) : random.pick(candidates)
    }

    private static func event(_ kind: Kind, _ random: inout SimRandom, names: [SimMacName], config: Config) -> SimEvent {
        let mac = random.pick(names)
        switch kind {
        case .edit: return .userEdit(mac: mac, unit: random.pick(config.units))
        case .delete: return .userDelete(mac: mac, unit: random.pick(config.units))
        case .importFile:
            let count = random.int(in: 1...3)
            return .userImport(mac: mac, units: (0..<count).map { _ in random.pick(config.units) })
        case .hotkey: return .setHotkey(mac: mac, action: random.pick(["toggle", "show", "hide"]), combo: random.int(in: 0...2))
        case .itemIcon: return .chooseItemIcon(mac: mac, item: random.pick(["com.a", "com.b"]))
        case .oversize: return .oversizeIcon(mac: mac)
        case .turn:
            switch random.int(in: 0...2) {
            case 0: return .turnOn(mac: mac, folder: random.pick(config.folders))
            case 1: return .turnOff(mac: mac)
            default: return .changeFolder(mac: mac, folder: random.pick(config.folders))
            }
        case .move27:
            return .moveApp27(mac: macs27(config, &random, names), bundle: random.pick(config.bundles), section: random.int(in: 0...2))
        case .profile:
            let target = macs27(config, &random, names)
            let profile = random.pick(config.profiles)
            switch random.int(in: 0...4) {
            case 0, 1: return .applyProfile(mac: target, profile: profile, byUser: random.chance(0.6))
            case 2: return .saveProfile(mac: target, profile: profile)
            case 3: return .renameProfile(mac: target, profile: profile)
            default: return .deleteProfile(mac: target, profile: profile)
            }
        case .advance:
            return .advance(milliseconds: random.pick([1_000, 2_000, 5_000, 6_000, 6_000, 30_000, 300_000, 7_200_000]))
        case .launch: return .launch(mac: mac)
        case .quit: return .quit(mac: mac)
        case .restart: return .restartApp(mac: mac)
        case .crash: return .crash(mac: mac)
        case .answer:
            let answer: SimAnswer = random.pick([.use, .use, .keep, .keep, .later, .cancel])
            return .answer(mac: mac, answer)
        case .autoPlace: return .autoPlace(mac: mac, unit: random.pick(config.units))
        case .learn: return .learn(mac: mac, key: random.pick(["KnownItemTags", "TitleChangingItemOwners"]))
        case .flag: return .setFlag(mac: mac, key: random.pick(["HasImportedIceSettings", "MacOS27LayoutSeeded"]))
        case .seed27: return .seed27(mac: macs27(config, &random, names))
        case .place27: return .placeNewApp27(mac: macs27(config, &random, names), bundle: random.pick(config.bundles))
        case .upgrade:
            let candidates = config.macs.filter { $0.generation == 26 }.map(\.name)
            return .upgradeOS(mac: candidates.isEmpty ? mac : random.pick(candidates))
        case .clock: return .clockStep(mac: mac, milliseconds: Int64(random.int(in: -3...3)) * 3_600_000)
        case .update: return .updateApp(mac: mac, version: random.pick(config.updateVersions))
        case .identity:
            let other = random.pick(names.filter { $0 != mac }.isEmpty ? names : names.filter { $0 != mac })
            switch random.int(in: 0...6) {
            case 0: return .clone(from: other, to: mac)
            case 1: return .copyAccount(from: other, to: mac)
            case 2: return .restorePrefs(mac: mac)
            case 3: return .restoreSigma(mac: mac)
            case 4: return .restoreHome(mac: mac, keepCaches: random.chance(0.5))
            case 5: return .sigmaLost(mac: mac)
            default: return .reinstall(mac: mac)
            }
        }
    }

    private static func fault(_ random: inout SimRandom, rates: SimFaultRates, names: [SimMacName], config: Config) -> SimEvent {
        let mac = random.pick(names)
        let folder = random.pick(config.folders)
        let path = random.pick(names.map { "holzBar/Macs/\($0.name).plist" } + [SimLimits.legacyPath])
        let policy = config.preset?.policy ?? .ideal
        let weights = [
            rates.restore, rates.delete, rates.deleteFolder, rates.evict, rates.exposePartial, rates.stall,
            rates.unmount, rates.foreign, rates.offline,
        ]
        var pick = random.unit() * weights.reduce(0, +)
        var index = weights.count
        for (position, rate) in weights.enumerated() {
            pick -= rate
            if pick <= 0 { index = position; break }
        }
        switch index {
        case 0: return .provider(.restore(folder: folder, path: path, version: random.int(in: 1...30)))
        case 1: return .provider(.delete(folder: folder, path: path))
        case 2: return .provider(.deleteFolder(folder: folder))
        case 3: return .provider(.evict(folder: folder, path: path, mac: mac))
        case 4:
            return .provider(.exposePartial(folder: folder, path: path, mac: mac, forMilliseconds: policy.typicalPartialMilliseconds))
        case 5:
            let forever = random.chance(0.15)
            return .provider(.stall(folder: folder, mac: mac, forMilliseconds: forever ? nil : policy.typicalStallMilliseconds))
        case 6: return .provider(.unmount(folder: folder, mac: mac))
        case 7: return .provider(.foreign(folder: folder, path: path, kind: random.pick(SimForeignKind.allCases)))
        case 8: return .provider(.offline(folder: folder, mac: mac, forMilliseconds: policy.typicalOfflineMilliseconds))
        default: break
        }
        return .provider(.mount(folder: folder, mac: mac))
    }
}

// MARK: - Runner

enum SimRunMode: Sendable {
    /// One seeded random trace of `steps` events.
    case random(steps: Int)
    /// Every sequence over `alphabet` up to `depth`, with visited-state hashing.
    case exhaustive(depth: Int, alphabet: [SimEvent])
}

struct SimRunResult: Sendable {
    var seed: UInt64
    var traceHash: String
    var violations: [SimViolation]
    var prompts: [SimPromptRecord]
    var writes: [SimWriteRecord]
    var events: [SimEvent]
    /// Distinct world states the exhaustive mode visited (the number of runs in random mode is 1).
    var visitedStates: Int
    var runs: Int
}

struct SimRunner {
    /// Runs one seed in a mode and returns what happened. In exhaustive mode the events and trace hash are those of
    /// the first violating sequence, or of the last sequence explored when there is none.
    static func run(
        seed: UInt64,
        preset: SimProviderPreset?,
        macs: [SimMacSpec],
        brainFactory: @escaping SimWorld.BrainFactory,
        mode: SimRunMode,
        oracles: SimOracleSet = .safety,
        config: SimGenerator.Config? = nil,
        maximumRuns: Int = 20_000
    ) -> SimRunResult {
        func makeWorld() -> SimWorld {
            SimWorld(seed: seed, macs: macs, preset: preset, brainFactory: brainFactory, oracles: oracles)
        }
        func result(_ world: SimWorld, _ events: [SimEvent], visited: Int, runs: Int) -> SimRunResult {
            SimRunResult(
                seed: seed, traceHash: world.traceHash, violations: world.oracleViolations,
                prompts: world.stepRecords.flatMap(\.prompts), writes: world.writeLog, events: events,
                visitedStates: visited, runs: runs
            )
        }
        switch mode {
        case .random(let steps):
            var generator = config ?? SimGenerator.Config(macs: macs, preset: preset, steps: steps)
            generator.steps = steps
            let events = SimGenerator.events(seed: seed, generator)
            let world = makeWorld()
            world.run(events)
            return result(world, events, visited: 1, runs: 1)
        case .exhaustive(let depth, let alphabet):
            var visited: [String: Int] = [:]
            var frontier: [[SimEvent]] = [[]]
            var runs = 0
            var last = makeWorld()
            var lastEvents: [SimEvent] = []
            for level in 0..<max(depth, 0) {
                // The runs left are shared by the levels left, and a level too large for its share is sampled at an even stride,
                // so a cap never leaves the deeper levels unvisited.
                let share = max((maximumRuns - runs) / (depth - level), 1)
                let candidates = frontier.count * alphabet.count
                let stride = max((candidates + share - 1) / share, 1)
                var next: [[SimEvent]] = []
                var position = 0
                for prefix in frontier {
                    for event in alphabet {
                        defer { position += 1 }
                        guard runs < maximumRuns, position % stride == 0 else { continue }
                        let events = prefix + [event]
                        let world = makeWorld()
                        world.run(events)
                        runs += 1
                        last = world
                        lastEvents = events
                        if !world.oracleViolations.isEmpty {
                            return result(world, events, visited: visited.count, runs: runs)
                        }
                        let digest = world.stateDigest
                        let remaining = depth - level - 1
                        if let known = visited[digest], known >= remaining { continue }
                        visited[digest] = remaining
                        next.append(events)
                    }
                }
                frontier = next
                if frontier.isEmpty { break }
            }
            return result(last, lastEvents, visited: visited.count, runs: runs)
        }
    }
}
