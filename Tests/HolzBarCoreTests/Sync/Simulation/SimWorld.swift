import Foundation

/// How a Mac starts in a world.
struct SimMacSpec: Sendable {
    var name: SimMacName
    var version: SimMacVersion
    var generation = 26
    /// Sync is turned on at the start, pointing at `folder`.
    var enabled = true
    var folder: String? = "F1"
    var running = false
    var defaults: [String: SimValue] = [:]
    var clockOffsetMilliseconds: Int64 = 0
    /// A folder the provider keeps on this Mac's disk although sync is not turned on for it: a Mac that is
    /// about to join a folder its user already syncs with the provider.
    var syncedFolder: String?
    /// Further folders the provider keeps on this Mac's disk (a Mac that is about to change its folder to one of them).
    var alsoOnDisk: [String] = []

    init(
        _ name: SimMacName,
        _ version: SimMacVersion,
        generation: Int = 26,
        enabled: Bool = true,
        folder: String? = "F1",
        running: Bool = false,
        defaults: [String: SimValue] = [:],
        clockOffsetMilliseconds: Int64 = 0,
        syncedFolder: String? = nil,
        alsoOnDisk: [String] = []
    ) {
        self.alsoOnDisk = alsoOnDisk
        self.name = name
        self.version = version
        self.generation = generation
        self.enabled = enabled
        self.folder = folder
        self.running = running
        self.defaults = defaults
        self.clockOffsetMilliseconds = clockOffsetMilliseconds
        self.syncedFolder = syncedFolder
    }
}

/// The deterministic multi-Mac world: seeded randomness, a virtual clock with per-Mac offsets, per-Mac
/// folder replicas behind a provider, and one append-only trace. No real time, no system randomness and
/// no real concurrency: one seed gives one trace, and the trace hash proves it.
final class SimWorld {
    typealias BrainFactory = (SimMacVersion, SimMacName) -> any SimSyncBrain

    /// The brain each Mac kind gets unless the world is built with another factory.
    static func defaultBrain(for version: SimMacVersion, mac: SimMacName) -> any SimSyncBrain {
        switch version {
        case .beta1: SimMacBeta1()
        case .beta2: SimMacBeta2()
        case .redesign, .redesignSkew: SimInertBrain(kind: version)
        }
    }

    let seed: UInt64
    private(set) var random: SimRandom
    private(set) var clock = SimClock()
    private(set) var providers: [String: SimProvider] = [:]
    private(set) var macs: [SimMacName: SimMacState] = [:]
    private(set) var brains: [SimMacName: any SimSyncBrain] = [:]
    /// The append-only trace: one canonical line per event, write, ingest, prompt and delivery.
    private(set) var trace: [String] = []
    /// The ground truth: vector clocks over this run's events, never fed by engine metadata.
    let groundTruth = SimGroundTruth()
    /// The longest a coordinated call blocks before the caller gives up.
    var ioTimeoutMilliseconds: Int64 = 5_000

    /// The oracles this world runs at each moment, and what they found.
    var oracles: SimOracleSet
    private(set) var stepIndex = 0
    private(set) var stepRecords: [SimStepRecord] = []
    private(set) var oracleViolations: [SimViolation] = []
    /// Called when an oracle reports a violation, with the world as it is then (for debugging a failing seed).
    var violationObserver: ((SimViolation, SimWorld) -> Void)?
    /// The thing just observed, while an oracle runs.
    private(set) var focus: SimFocus?
    private(set) var currentStep: SimStepRecord?
    /// What the drain phase found, for the liveness oracles (`SimDrain.run` sets it).
    var drainFacts: SimDrainFacts?
    /// Values the oracles compute once per world (the digests of the planted markers).
    let oracleCache = SimOracleCache()
    /// Every write handed to a provider, in order.
    private(set) var writeLog: [SimWriteRecord] = []
    /// The build of the Mac that wrote each provider version, at the time of the write.
    private(set) var writerBuilds: [Int: SimMacVersion] = [:]
    private var violationKeys = Set<String>()
    private var sessionReads: [SimMacName: [String: Int]] = [:]
    private var sessionWrites: [SimMacName: [String: Int]] = [:]
    private var knownWriteViolations = 0

    private let brainFactory: BrainFactory
    private let policy: SimFaultPolicy
    private var timers: [SimTimer] = []
    private var crashPlans: [SimMacName: Int] = [:]
    private var timerSequence = 0
    private var userTokenCounter = 0
    private var autoTokenCounter = 0
    private var backups: [SimMacName: SimMacBackup] = [:]
    private var registeredVersions: [String: Int] = [:]
    private var versionTokens: [Int: (path: String, tokens: Set<String>)] = [:]
    /// Whether the step in progress is the sync peer's own doing (see `SimStepCause`).
    private var activeCause = SimStepCause.sync

    private struct SimTimer {
        var time: Int64
        var sequence: Int
        var mac: SimMacName
        var tag: String
    }

    private struct SimMacBackup {
        var defaults: [String: SimValue]
        var sigma: Data?
        var caches: Data?
        var enabled: Bool
        var folderID: String?
        /// The folder of the join that waited at that moment: it is part of the sync state (`pendingJoin.folderIdentity`).
        var pendingFolderID: String?
        /// What the sync state of that moment knew, for the ground truth when the state comes back.
        var knowledge: SimGroundTruth.Knowledge
    }

    /// - Parameters:
    ///   - preset: the provider preset; without it (and without `policy`) the provider is ideal: no delay, no faults.
    ///   - policy: an explicit fault policy, which wins over `preset`.
    init(
        seed: UInt64,
        macs specs: [SimMacSpec],
        preset: SimProviderPreset? = nil,
        policy: SimFaultPolicy? = nil,
        brainFactory: BrainFactory? = nil,
        oracles: SimOracleSet = .none
    ) {
        self.seed = seed
        self.oracles = oracles
        self.policy = policy ?? preset?.policy ?? .ideal
        random = SimRandom(seed: seed)
        self.brainFactory = brainFactory ?? { SimWorld.defaultBrain(for: $0, mac: $1) }
        for spec in specs {
            let name = spec.name
            var state = SimMacState(
                name: name,
                version: spec.version,
                markers: SimIdentityMarkers(mac: name),
                uid: 501,
                generation: spec.generation,
                random: random.fork("mac-\(name.name)")
            )
            groundTruth.buildOfMac[name] = spec.version
            state.defaults = spec.defaults
            state.enabled = spec.enabled && spec.folder != nil
            state.folderID = spec.folder
            macs[name] = state
            groundTruth.setGeneration(spec.generation, of: name)
            brains[name] = self.brainFactory(spec.version, name)
            clock.setOffset(spec.clockOffsetMilliseconds, of: name)
            if let folder = spec.folder ?? spec.syncedFolder { ensureReplica(of: name, in: folder) }
            for folder in spec.alsoOnDisk { ensureReplica(of: name, in: folder) }
        }
        groundTruth.holderSource = { [unowned self] in self.holderSnapshot() }
        for spec in specs where spec.running {
            step(.launch(mac: spec.name))
        }
    }

    // MARK: Queries

    var now: Int64 { clock.now }

    func state(of mac: SimMacName) -> SimMacState { macs[mac]! }
    func defaults(of mac: SimMacName) -> [String: SimValue] { macs[mac]?.defaults ?? [:] }
    func brain(of mac: SimMacName) -> any SimSyncBrain { brains[mac]! }
    func replica(of mac: SimMacName, folder: String = "F1") -> SimFolderReplica {
        providers[folder]?.replica(of: mac) ?? SimFolderReplica()
    }

    /// Writes attempted on an unmounted folder, across all folders (violation candidates for the oracles).
    var violations: [SimWriteViolation] {
        providers.keys.sorted().flatMap { providers[$0]!.violations }
    }

    /// SHA-256 over the canonical text of every event and write, in order.
    var traceHash: String { SimDigest.hex(of: trace.joined(separator: "\n")) }

    // MARK: Stepping

    /// Runs one event, records what it did and runs the step oracles.
    func step(_ event: SimEvent) {
        stepIndex += 1
        currentStep = SimStepRecord(index: stepIndex, event: event, time: clock.now, before: snapshots())
        stepBody(event)
        let writeViolationCount = violations.count
        currentStep?.writeViolationsAdded = writeViolationCount - knownWriteViolations
        knownWriteViolations = writeViolationCount
        currentStep?.after = snapshots()
        if let record = currentStep {
            currentStep = nil
            stepRecords.append(record)
            runOracles(.step, focus: .step(record), event: event)
        }
    }

    private func stepBody(_ event: SimEvent) {
        record("E \(event.canonical)")
        groundTruth.recordEvent(event.canonical, time: clock.now)
        let cause = stepCause(of: event)
        activeCause = cause
        switch event {
        case .advance(let milliseconds):
            advanceTime(to: clock.now + max(0, milliseconds))
        case .clockStep(let mac, let milliseconds):
            clock.step(mac, by: milliseconds)
        case .timerFired(let mac, let tag):
            fire(mac: mac, tag: tag)
        case .provider(let providerEvent):
            handleProvider(providerEvent)
        case .launch(let mac): launch(mac)
        case .quit(let mac): quit(mac)
        case .crash(let mac): die(mac)
        case .restartApp(let mac):
            if macs[mac]?.running == true {
                quit(mac)
                launch(mac)
            }
        case .updateApp(let mac, let version): update(mac, to: version)
        case .upgradeOS(let mac):
            guard macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.generation = 27
            groundTruth.setGeneration(27, of: mac)
        case .rekeyItem(let mac, let from, let to):
            rekey(mac, from: from, to: to)
        case .defaultsWriteWhileQuit(let mac, let unit, let value):
            // The user's `defaults write` while the app is quit: the preferences change, no brain hears of it.
            guard macs[mac]?.running == false else { return }
            SimUnits.set(unit, to: value, in: &macs[mac]!.defaults)
            groundTruth.recordUserChange(mac: mac, unit: unit, tokens: value?.tokens ?? [], time: clock.now)
        case .clone, .copyAccount, .duplicateInstallation, .restorePrefs, .restoreSigma, .restoreHome, .sigmaLost, .reinstall:
            handleIdentity(event)
            // Replaced settings are what the user knows now.
            switch event {
            case .clone(_, let target), .copyAccount(_, let target), .duplicateInstallation(_, let target), .restorePrefs(let target),
                 .restoreHome(let target, _), .reinstall(let target):
                if let defaults = macs[target]?.defaults {
                    var preferencesOnly = false
                    if case .restorePrefs = event { preferencesOnly = true }
                    groundTruth.resetInformed(mac: target, tokens: SimUnits.tokens(in: defaults), identityKept: preferencesOnly)
                }
            default:
                break
            }
            for target in identityTargets(of: event) + Self.stateReplacedOnly(event) {
                guard let defaults = macs[target]?.defaults else { continue }
                let held = SimUnits.tokens(in: defaults)
                groundTruth.engineKeeps(mac: target, tokens: held)
                if let applied = SimMacRedesignProbe.appliedTokens(of: self, target) {
                    groundTruth.markPre(tokens: held.subtracting(applied))
                }
            }
        case .turnOn(let mac, let folder):
            command(.turnOn(folder: folder), on: mac)
        case .turnOff(let mac):
            command(.turnOff, on: mac)
        case .changeFolder(let mac, let folder):
            command(.changeFolder(folder: folder), on: mac)
        case .answer(let mac, let answer):
            answerPrompt(answer, on: mac)
        case .userEdit, .userDelete, .userImport, .setHotkey, .chooseItemIcon, .oversizeIcon, .moveApp27,
             .applyProfile, .saveProfile, .renameProfile, .deleteProfile:
            handleUser(event)
        case .autoPlace, .learn, .setFlag, .seed27, .placeNewApp27:
            handleAutomatic(event)
        }
        // Deliveries and timers due at this very instant (no delay) run before the next event.
        if case .advance = event {} else { advanceTime(to: clock.now) }
        flushProviderLogs()
        registerProviderVersions()
        groundTruth.observe(cause: cause, time: clock.now)
    }

    /// Whether a step is the sync peer's own doing or something else that may destroy a holder.
    private func stepCause(of event: SimEvent) -> SimStepCause {
        switch event {
        case .provider, .userEdit, .defaultsWriteWhileQuit, .userDelete, .userImport, .setHotkey, .chooseItemIcon, .oversizeIcon, .moveApp27,
             .applyProfile, .saveProfile, .renameProfile, .deleteProfile, .autoPlace, .learn, .setFlag, .seed27,
             .placeNewApp27, .clone, .copyAccount, .duplicateInstallation, .restorePrefs, .restoreSigma, .restoreHome, .sigmaLost,
             .reinstall, .crash, .upgradeOS, .rekeyItem:
            return .nonSync
        case .launch(let mac), .restartApp(let mac), .updateApp(let mac, _):
            return macs[mac]?.version == .beta2 ? .nonSync : .sync
        default:
            return .sync
        }
    }

    /// Runs a list of events.
    func run(_ events: [SimEvent]) {
        for event in events { step(event) }
    }

    /// Lets virtual time pass.
    func advance(seconds: Int64) {
        step(.advance(milliseconds: seconds * 1000))
    }

    // MARK: Tokens

    /// A fresh `u<k>@<unit>` token for a user change.
    func mintUserToken(unit: String) -> SimValue {
        userTokenCounter += 1
        return .userToken(userTokenCounter, unit: unit)
    }

    /// A fresh `auto-<mac>-<k>` token for an automatic change.
    func mintAutoToken(mac: SimMacName) -> SimValue {
        autoTokenCounter += 1
        return .autoToken(mac: mac, autoTokenCounter)
    }

    // MARK: Time

    private func advanceTime(to target: Int64) {
        while true {
            var candidate: Int64?
            for folder in providers.keys.sorted() {
                if let due = providers[folder]!.nextDeliveryTime { candidate = min(candidate ?? due, due) }
            }
            if let due = timers.map(\.time).min() { candidate = min(candidate ?? due, due) }
            guard let due = candidate, due <= target else { break }
            let at = max(due, clock.now)
            // What the step did so far belongs to the step; what the provider delivers belongs to the provider.
            groundTruth.observe(cause: activeCause, time: clock.now)
            moveClock(to: at)
            for folder in providers.keys.sorted() {
                guard let providerDue = providers[folder]!.nextDeliveryTime, providerDue <= at else { continue }
                let notices = providers[folder]!.deliverDue(until: at)
                flushProviderLog(folder)
                groundTruth.observe(cause: .nonSync, time: at)
                signal(notices, folder: folder)
            }
            let dueTimers = timers.filter { $0.time <= at }.sorted {
                ($0.time, $0.sequence) < ($1.time, $1.sequence)
            }
            timers.removeAll { $0.time <= at }
            for timer in dueTimers {
                record("T \(timer.mac) \(timer.tag)")
                fire(mac: timer.mac, tag: timer.tag)
            }
        }
        moveClock(to: target)
    }

    private func moveClock(to time: Int64) {
        clock.advance(to: time)
        for folder in providers.keys.sorted() {
            providers[folder]!.now = time
            providers[folder]!.settle(at: time)
        }
    }

    private func signal(_ notices: [SimDeliveryNotice], folder: String) {
        guard providers[folder]?.signalsFolderChanges == true else { return }
        var seen = Set<SimMacName>()
        for notice in notices where seen.insert(notice.mac).inserted {
            guard let state = macs[notice.mac], state.running, state.enabled, state.folderID == folder else { continue }
            runHook(notice.mac, .folderSignal) { brain, context in brain.folderSignal(&context) }
        }
    }

    private func fire(mac: SimMacName, tag: String) {
        guard macs[mac]?.running == true else { return }
        runHook(mac, .timer) { brain, context in brain.timerFired(tag: tag, &context) }
    }

    // MARK: Hooks

    /// Runs a hook against a Mac's brain with a fresh context and carries out what it recorded.
    @discardableResult
    private func runHook(
        _ mac: SimMacName,
        _ name: SimHookName,
        answered: SimAnsweredPrompt? = nil,
        folderOverride: String? = nil,
        _ body: (inout any SimSyncBrain, inout SimMacContext) -> Void
    ) -> Bool {
        guard var state = macs[mac], var brain = brains[mac] else { return false }
        let before = state.defaults
        let replica: SimFolderReplica
        // A join reads the folder the user chose, which is not the sync folder yet.
        if let folder = folderOverride ?? state.pendingFolderID ?? state.folderID {
            replica = providers[folder]?.replica(of: mac) ?? SimFolderReplica()
        } else {
            replica = SimFolderReplica()
        }
        var context = SimMacContext(
            mac: mac,
            state: state,
            wallClock: clock.wallClock(of: mac),
            replica: replica,
            globalNow: clock.now,
            ioTimeoutMilliseconds: ioTimeoutMilliseconds
        )
        context.crashAfterEffects = crashPlans[mac]
        var hook = SimHookRecord(
            mac: mac, name: name, stepIndex: stepIndex, brainKind: state.version,
            syncCaused: state.version != .beta2, changeCountBefore: groundTruth.changes.count,
            blockedMilliseconds: 0
        )
        hook.answered = answered
        hook.openPromptAtStart = brain.openPrompt
        body(&brain, &context)
        brains[mac] = brain
        state.defaults = context.defaults
        // The user sees the settings the Mac holds, so a value that landed in them is known now; a value
        // that was only merged is not.
        groundTruth.recordInformed(mac: mac, tokens: SimUnits.tokens(in: context.defaults))
        if let report = introspection(of: mac)?.report(), report.joining, report.joinCommitted { groundTruth.recordJoinCommit(mac: mac) }
        if let answered = hook.answered, answered.answer != .later, answered.answer != .cancel {
            // A row the engine did not decide (it was decided elsewhere, or the user changed it after the sheet showed it) is no part of
            // the answer, and the question about it that follows in the same hook is judged against the answer as it was.
            groundTruth.leaveOut(mac: mac, prompt: answered.prompt, units: introspection(of: mac)?.answerLeftOutUnits() ?? [])
            // The answer asserts the value the settings hold after it, whichever the sheet listed (the engine answers against its state,
            // which may hold a value the sheet did not show).
            let held = Set(answered.prompt.shown.map(\.unit)).flatMap { SimUnits.value(of: $0, in: context.defaults)?.tokens ?? [] }
            groundTruth.assertHeld(mac: mac, tokens: held)
        }
        state.sigma = context.sigma
        state.caches = context.caches
        state.random = context.random
        state.enabled = context.enabled
        state.folderID = context.folderID
        state.pendingFolderID = context.pendingFolderID
        macs[mac] = state
        if let folder = state.folderID { ensureReplica(of: mac, in: folder) }
        if let folder = state.pendingFolderID { ensureReplica(of: mac, in: folder) }
        hook.blockedMilliseconds = context.blockedMilliseconds
        for action in context.actions {
            if case .ingest(let version) = action { hook.ingests.append(version) }
            if case .merged(let version) = action { hook.ingests.append(version) }
        }
        hook.transitions = Self.transitions(of: mac, before: before, after: context.defaults)
        hook.keyChanges = Self.keyChanges(of: mac, before: before, after: context.defaults)
        for entry in context.readLog {
            var version = 0
            if case .data(_, let read) = entry.result { version = read }
            let read = SimReadRecord(
                mac: mac, entry: entry, version: version, replicaVersion: max(replica.versions[entry.path] ?? 0, 0),
                versionKind: version > 0 ? kind(ofVersion: version) : nil,
                versionWriter: version > 0 ? writer(ofVersion: version) : nil, stepIndex: stepIndex, hook: name
            )
            hook.reads.append(read)
            if version > 0 { sessionReads[mac, default: [:]][entry.path] = version }
        }
        process(context.actions, of: mac, before: before, hook: &hook)
        if context.crashed {
            // The crash the test asked for: the effects before it happened, the Mac is gone.
            crashPlans[mac] = nil
            record("CRASH \(mac) after \(context.effectsRun) effects")
            die(mac)
        }
        currentStep?.hooks.append(hook)
        for read in hook.reads { runOracles(.read, focus: .read(read), event: currentStep?.event) }
        return true
    }

    /// Makes the Mac crash after it carried out `count` effects in a hook (the next hook that has
    /// that many): the process dies with whatever was persisted by then, and a later launch
    /// starts from that. The brain asks the context after every effect.
    func crashAfterEffect(_ count: Int, on mac: SimMacName) {
        crashPlans[mac] = max(count, 1)
    }

    private static func transitions(
        of mac: SimMacName, before: [String: SimValue], after: [String: SimValue]
    ) -> [SimTransition] {
        var old: [String: SimValue] = [:]
        var new: [String: SimValue] = [:]
        for (unit, value) in SimUnits.units(of: before) { old[unit] = value }
        for (unit, value) in SimUnits.units(of: after) { new[unit] = value }
        var result: [SimTransition] = []
        for unit in Set(old.keys).union(new.keys).sorted() where old[unit] != new[unit] {
            result.append(SimTransition(mac: mac, unit: unit, old: old[unit], new: new[unit]))
        }
        return result
    }

    private static func keyChanges(
        of mac: SimMacName, before: [String: SimValue], after: [String: SimValue]
    ) -> [SimKeyChange] {
        var result: [SimKeyChange] = []
        for key in Set(before.keys).union(after.keys).sorted() where before[key] != after[key] {
            result.append(SimKeyChange(mac: mac, key: key, old: before[key], new: after[key]))
        }
        return result
    }

    private func process(
        _ actions: [SimMacAction], of mac: SimMacName, before: [String: SimValue], hook: inout SimHookRecord
    ) {
        var relaunch = false
        var ingestedSoFar: [Int] = []
        for action in actions {
            switch action {
            case .write(let folder, let path, let data):
                ensureReplica(of: mac, in: folder)
                providers[folder]!.now = clock.now
                let previousReplica = providers[folder]!.replica(of: mac)
                let previousEntry = previousReplica.entry(path)
                let previousVersion = max(previousReplica.versions[path] ?? 0, 0)
                var dominated = true
                if previousVersion > 0 {
                    dominated = groundTruth.past(ofVersion: previousVersion).isSubset(of: groundTruth.claimablePast(ofMac: mac))
                }
                let seen = previousVersion > 0
                    && (sessionReads[mac]?[path] == previousVersion || sessionWrites[mac]?[path] == previousVersion)
                let outcome = providers[folder]!.write(from: mac, path: path, data: data)
                flushProviderLog(folder)
                var newVersion: Int?
                if case .written(let version) = outcome {
                    newVersion = version
                    groundTruth.recordWrite(version: version, writer: mac, path: path, time: clock.now)
                    sessionWrites[mac, default: [:]][path] = version
                    record("W \(mac) \(folder) \(path) v\(version) \(SimDigest.canonicalRendering(of: data))")
                } else {
                    record("W! \(mac) \(folder) \(path) \(outcome)")
                }
                let write = SimWriteRecord(
                    mac: mac, folder: folder, path: path, data: data, version: newVersion, time: clock.now,
                    stepIndex: stepIndex, brainKind: macs[mac]?.version ?? .beta1,
                    changeCount: groundTruth.changes.count, previousEntry: previousEntry,
                    previousVersion: previousVersion, previousDominated: dominated, previousSeenInSession: seen,
                    previousKind: previousVersion > 0 ? kind(ofVersion: previousVersion) : nil,
                    previousWriter: previousVersion > 0 ? writer(ofVersion: previousVersion) : nil,
                    hook: hook.name, ingestsSoFar: ingestedSoFar, unmounted: newVersion == nil
                )
                hook.writes.append(write)
                writeLog.append(write)
                if let version = newVersion { writerBuilds[version] = write.brainKind }
                runOracles(.write, focus: .write(write), event: currentStep?.event)
            case .ingest(let version), .merged(let version):
                if groundTruth.versions[version] != nil,
                   groundTruth.past(ofVersion: version).isSubset(of: groundTruth.seenPast(ofMac: mac)) {
                    // A file whose past is empty but which carries a value (one that no user change made: an automatic placement that
                    // a Mac whose state was lost published as its own) is no version that a Mac can have seen.
                    var carriesValue = false
                    if let path = path(ofVersion: version), let data = data(ofVersion: version),
                       let tokens = brains[mac]?.heldTokens(inFile: path, data: data) {
                        carriesValue = tokens.contains { groundTruth.origin(of: $0) == .automatic }
                            || (groundTruth.past(ofVersion: version).isEmpty && !tokens.isEmpty)
                    }
                    if !carriesValue { hook.dominatedIngests.append(version) }
                }
                if case .merged = action {
                    groundTruth.recordMerge(mac: mac, version: version, time: clock.now)
                } else {
                    groundTruth.recordIngest(mac: mac, version: version, time: clock.now)
                }
                ingestedSoFar.append(version)
                if let path = path(ofVersion: version) { sessionReads[mac, default: [:]][path] = version }
                record("I \(mac) v\(version)")
            case .promptShown(let prompt):
                groundTruth.recordPrompt(mac: mac, prompt: prompt, time: clock.now)
                record("Q \(mac) #\(prompt.id) \(prompt.title) \(prompt.shown.count)")
                hook.prompts.append(prompt)
                let promptRecord = SimPromptRecord(
                    mac: mac, prompt: prompt, stepIndex: stepIndex, time: clock.now, hook: hook.name,
                    openBefore: hook.openPromptAtStart, newIngests: hook.ingests.filter { !hook.dominatedIngests.contains($0) }
                )
                currentStep?.prompts.append(promptRecord)
                runOracles(.prompt, focus: .prompt(promptRecord), event: currentStep?.event)
            case .requestDownload(let folder, let path):
                providers[folder]?.requestDownload(path: path, mac: mac)
                flushProviderLog(folder)
            case .schedule(let after, let tag):
                timerSequence += 1
                timers.append(SimTimer(time: clock.now + max(0, after), sequence: timerSequence, mac: mac, tag: tag))
            case .cancelTimer(let tag):
                timers.removeAll { $0.mac == mac && $0.tag == tag }
            case .resolveConflictVersions(let folder, let path):
                providers[folder]?.resolveConflictVersions(path: path, mac: mac)
            case .automaticWrite(let unit):
                let changed = SimUnits.value(of: unit, in: before) != SimUnits.value(of: unit, in: macs[mac]?.defaults ?? [:])
                record("AUTO \(mac) \(unit) changed=\(changed)")
            case .relaunch:
                relaunch = true
            case .note(let text):
                record("N \(mac) \(text)")
            }
        }
        registerProviderVersions()
        if relaunch, macs[mac]?.running == true {
            quit(mac)
            launch(mac)
        }
    }

    private func flushProviderLog(_ folder: String) {
        for line in providers[folder]?.drainLog() ?? [] { record("P \(folder) \(line)") }
    }

    private func record(_ line: String) {
        trace.append("\(clock.now) \(line)")
    }

    private func ensureReplica(of mac: SimMacName, in folder: String) {
        if providers[folder] == nil {
            providers[folder] = makeProvider(folder: folder)
        }
        providers[folder]!.now = clock.now
        providers[folder]!.ensureReplica(for: mac, computerName: macs[mac]?.markers.computerName)
    }

    private func makeProvider(folder: String) -> SimProvider {
        SimProvider(
            policy: policy, random: random.fork("provider-\(folder)"),
            firstVersionID: providers.count * 1_000_000 + 1
        )
    }

    private func flushProviderLogs() {
        for folder in providers.keys.sorted() { flushProviderLog(folder) }
    }

    // MARK: Lifecycle

    private func launch(_ mac: SimMacName) {
        guard var state = macs[mac], !state.running else { return }
        backups[mac] = SimMacBackup(
            defaults: state.defaults, sigma: state.sigma, caches: state.caches,
            enabled: state.enabled, folderID: state.folderID, pendingFolderID: state.pendingFolderID, knowledge: groundTruth.knowledge(of: mac)
        )
        state.running = true
        macs[mac] = state
        sessionReads[mac] = [:]
        sessionWrites[mac] = [:]
        runHook(mac, .launch) { brain, context in brain.launch(&context) }
    }

    private func quit(_ mac: SimMacName) {
        guard macs[mac]?.running == true else { return }
        runHook(mac, .quit) { brain, context in brain.quit(&context) }
        macs[mac]?.running = false
        sessionReads[mac] = [:]
        sessionWrites[mac] = [:]
        timers.removeAll { $0.mac == mac }
    }

    /// The process dies without running quit code.
    private func die(_ mac: SimMacName) {
        guard macs[mac] != nil else { return }
        macs[mac]?.running = false
        sessionReads[mac] = [:]
        sessionWrites[mac] = [:]
        brains[mac]?.processDied()
        timers.removeAll { $0.mac == mac }
    }

    private func update(_ mac: SimMacName, to version: SimMacVersion) {
        guard macs[mac] != nil else { return }
        quit(mac)
        // The same build again changes nothing: the brain keeps what the harness records next to it.
        guard macs[mac]?.version != version else { return }
        let wasLegacy = macs[mac]?.version == .beta1 || macs[mac]?.version == .beta2
        macs[mac]?.version = version
        groundTruth.buildOfMac[mac] = version
        // The first run of a redesigned build finds the settings of the build before it with no state of its own: what they hold was
        // there before sync knew of it (a join treats it so), and the changes made under a build that sent no intents are no changes
        // the engine saw.
        if wasLegacy, Self.isRedesign(build: version), let defaults = macs[mac]?.defaults {
            groundTruth.markPre(tokens: SimUnits.tokens(in: defaults))
        }
        let previous = brains[mac]
        brains[mac] = brainFactory(version, mac)
        if let old = previous as? SimMacRedesign, var new = brains[mac] as? SimMacRedesign {
            new.carryBookkeeping(from: old)
            brains[mac] = new
        }
    }

    private func handleIdentity(_ event: SimEvent) {
        switch event {
        case .clone(let from, let to):
            guard let source = macs[from], macs[to] != nil, from != to else { return }
            die(to)
            brains[to]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: to, with: groundTruth.knowledge(of: from))
            macs[to]?.defaults = source.defaults
            macs[to]?.sigma = source.sigma
            macs[to]?.caches = source.caches
            macs[to]?.enabled = source.enabled
            macs[to]?.folderID = source.folderID
            // The folder of a join that waits is part of the sync state that the copy carries; the Mac reads that folder, not an empty one.
            macs[to]?.pendingFolderID = source.pendingFolderID
            if let folder = source.folderID { ensureReplica(of: to, in: folder) }
            if let folder = source.pendingFolderID { ensureReplica(of: to, in: folder) }
        case .copyAccount(let from, let to):
            guard let source = macs[from], macs[to] != nil, from != to else { return }
            die(to)
            brains[to]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: to, with: groundTruth.knowledge(of: from))
            macs[to]?.defaults = source.defaults
            macs[to]?.sigma = source.sigma
            macs[to]?.caches = source.caches
            macs[to]?.enabled = source.enabled
            macs[to]?.folderID = source.folderID
            // The folder of a join that waits is part of the sync state that the copy carries; the Mac reads that folder, not an empty one.
            macs[to]?.pendingFolderID = source.pendingFolderID
            macs[to]?.markers.hardwareID = source.markers.hardwareID
            // Another user account on the same Mac: the same hardware, another user ID.
            macs[to]?.uid = source.uid + 1
            if let folder = source.folderID { ensureReplica(of: to, in: folder) }
            if let folder = source.pendingFolderID { ensureReplica(of: to, in: folder) }
        case .duplicateInstallation(let source, let target):
            // A second installation of one Mac: the same hardware, the same account, the same preferences and sync
            // state, so the hash that binds the ID to the Mac still matches and the ID stays.
            guard let from = macs[source], macs[target] != nil, source != target else { return }
            die(target)
            brains[target]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: target, with: groundTruth.knowledge(of: source))
            macs[target]?.defaults = from.defaults
            macs[target]?.sigma = from.sigma
            macs[target]?.caches = from.caches
            macs[target]?.enabled = from.enabled
            macs[target]?.folderID = from.folderID
            macs[target]?.pendingFolderID = from.pendingFolderID
            macs[target]?.markers.hardwareID = from.markers.hardwareID
            macs[target]?.uid = from.uid
            if let folder = from.folderID { ensureReplica(of: target, in: folder) }
            if let folder = from.pendingFolderID { ensureReplica(of: target, in: folder) }
        case .restorePrefs(let mac):
            // Only the preferences go back (a restore of ~/Library/Preferences): the sync state stays.
            guard let backup = backups[mac], macs[mac] != nil else { return }
            groundTruth.recordPreferencesRestored(mac: mac)
            die(mac)
            brains[mac]?.stateWasReplaced()
            macs[mac]?.defaults = backup.defaults
            macs[mac]?.enabled = backup.enabled
            macs[mac]?.folderID = backup.folderID
        case .restoreSigma(let mac):
            guard let backup = backups[mac], macs[mac] != nil else { return }
            die(mac)
            brains[mac]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: mac, with: backup.knowledge)
            macs[mac]?.sigma = backup.sigma
            macs[mac]?.pendingFolderID = backup.pendingFolderID
        case .restoreHome(let mac, let keepCaches):
            guard let backup = backups[mac], macs[mac] != nil else { return }
            die(mac)
            brains[mac]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: mac, with: backup.knowledge)
            macs[mac]?.defaults = backup.defaults
            macs[mac]?.sigma = backup.sigma
            macs[mac]?.enabled = backup.enabled
            macs[mac]?.folderID = backup.folderID
            macs[mac]?.pendingFolderID = backup.pendingFolderID
            if !keepCaches { macs[mac]?.caches = nil }
        case .sigmaLost(let mac):
            guard macs[mac] != nil else { return }
            die(mac)
            brains[mac]?.stateWasReplaced()
            groundTruth.replaceKnowledge(of: mac, with: nil)
            macs[mac]?.sigma = nil
        case .reinstall(let mac):
            guard macs[mac] != nil else { return }
            die(mac)
            groundTruth.replaceKnowledge(of: mac, with: nil)
            macs[mac]?.defaults = [:]
            macs[mac]?.sigma = nil
            macs[mac]?.caches = nil
            macs[mac]?.enabled = false
            macs[mac]?.folderID = nil
            brains[mac] = brainFactory(macs[mac]!.version, mac)
        default:
            break
        }
        // Settings that carry no device ID (a copy of a Mac that never synced, a restore from before) give a Mac with no identity: its
        // next launch makes the first one, which is no change of an ID the brain remembers.
        for target in identityTargets(of: event) where isRedesign(target) && macs[target]?.defaults[SimMacRedesign.deviceIDKey] == nil {
            brains[target] = brainFactory(macs[target]!.version, target)
        }
    }

    private static func stateReplacedOnly(_ event: SimEvent) -> [SimMacName] {
        switch event {
        case .restoreSigma(let mac), .sigmaLost(let mac), .reinstall(let mac): return [mac]
        default: return []
        }
    }

    private func identityTargets(of event: SimEvent) -> [SimMacName] {
        switch event {
        case .clone(_, let target), .copyAccount(_, let target), .duplicateInstallation(_, let target), .restorePrefs(let target),
             .restoreHome(let target, _):
            return [target]
        default:
            return []
        }
    }

    // MARK: User and automatic events

    private func command(_ command: SimUserCommand, on mac: SimMacName) {
        guard macs[mac]?.running == true else { return }
        var chosen: String?
        if case .turnOn(let folder) = command { ensureReplica(of: mac, in: folder); chosen = folder }
        if case .changeFolder(let folder) = command { ensureReplica(of: mac, in: folder); chosen = folder }
        // The join reads the folder the user chose before it is the sync folder.
        runHook(mac, .command, folderOverride: chosen) { brain, context in brain.userCommand(command, &context) }
    }

    private func answerPrompt(_ answer: SimAnswer, on mac: SimMacName) {
        guard macs[mac]?.running == true, let prompt = brains[mac]?.openPrompt else {
            return
        }
        let hooksBefore = currentStep?.hooks.count ?? 0
        // The click is part of the Mac's past before anything the Mac does about it, so what the hook writes
        // comes after the answer. When the prompt is still open afterwards, the answer was refused: no answer.
        groundTruth.recordAnswer(mac: mac, prompt: prompt, answer: answer, time: clock.now)
        runHook(mac, .answer, answered: SimAnsweredPrompt(prompt: prompt, answer: answer)) { brain, context in
            brain.userCommand(.answer(answer), &context)
        }
        let hooks = Array((currentStep?.hooks ?? []).dropFirst(hooksBefore)).filter { $0.name == .answer && $0.mac == mac }
        // An answer that decided no row of the sheet (every row was decided elsewhere, or its setting changed since the sheet showed it)
        // is no answer: the user's click went to a sheet that no longer asked about the state, and the question about that state is a
        // new one.
        let leftOutAll: Bool = {
            guard answer != .later, answer != .cancel, let left = introspection(of: mac)?.answerLeftOutUnits() else { return false }
            let units = Set(prompt.shown.map(\.unit))
            return !units.isEmpty && units.isSubset(of: left)
        }()
        if brains[mac]?.openPrompt?.id == prompt.id || leftOutAll {
            groundTruth.retractAnswer(mac: mac, prompt: prompt)
        } else if answer != .later, answer != .cancel {
            // The sheet showed these values to the user, who decided. A user who answers Later has decided nothing: a
            // change made afterwards does not supersede the version that waits, and becomes a question (A1 S-04, A2 SC-14).
            // A row that the engine left out of the answer (the user changed its setting after the sheet showed it) is no answer: the
            // user decided nothing about it, and the values it showed are still to be decided.
            let leftOut = introspection(of: mac)?.answerLeftOutUnits() ?? []
            groundTruth.recordInformed(
                mac: mac, tokens: prompt.shown.filter { !leftOut.contains($0.unit) }.flatMap { [$0.local, $0.folder].compactMap { $0 } }
            )
        }
        // A sheet that is still open after the click was not answered: nothing happened that an oracle should judge as an answer.
        if brains[mac]?.openPrompt?.id == prompt.id || leftOutAll { return }
        let record = SimAnswerRecord(
            mac: mac, prompt: prompt, answer: answer, stepIndex: stepIndex, time: clock.now,
            transitions: hooks.flatMap(\.transitions), writes: hooks.flatMap(\.writes)
        )
        currentStep?.answers.append(record)
        runOracles(.answer, focus: .answer(record), event: currentStep?.event)
    }

    /// Applies a change to a running Mac's defaults and tells its brain.
    private func change(
        _ mac: SimMacName,
        origin: SimChangeOrigin,
        units: [String],
        _ mutate: (inout [String: SimValue]) -> Void
    ) {
        guard macs[mac]?.running == true else { return }
        mutate(&macs[mac]!.defaults)
        for unit in units.sorted() {
            let tokens = SimUnits.value(of: unit, in: macs[mac]!.defaults)?.tokens ?? []
            if origin == .user {
                groundTruth.recordUserChange(mac: mac, unit: unit, tokens: tokens, time: clock.now)
            } else {
                groundTruth.recordAutomaticChange(
                    mac: mac, unit: unit, tokens: tokens, time: clock.now, syncWasOff: macs[mac]?.folderID == nil || introspection(of: mac)?.report().joining == true
                )
            }
        }
        runHook(mac, .defaultsChanged) { brain, context in brain.defaultsChanged(origin: origin, units: units, &context) }
    }

    private func handleUser(_ event: SimEvent) {
        switch event {
        case .userEdit(let mac, let unit, let value):
            let newValue = value ?? mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: newValue, in: &$0) }
        case .userDelete(let mac, let unit):
            // Resetting a setting that holds no value changes nothing: there is no deletion to publish.
            guard let defaults = macs[mac]?.defaults, SimUnits.value(of: unit, in: defaults) != nil else { return }
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: nil, in: &$0) }
        case .userImport(let mac, let units):
            guard macs[mac]?.running == true else { return }
            let setUnits = units.sorted()
            var set: [(String, SimValue)] = []
            for unit in setUnits { set.append((unit, mintUserToken(unit: unit))) }
            var removed: [String] = []
            for key in SimKeys.importableKeys {
                let present = set.contains { SimUnits.parse($0.0).key == key }
                if !present, macs[mac]!.defaults[key] != nil { removed.append(key) }
            }
            let removedUnits = SimUnits.units(of: macs[mac]!.defaults).map(\.unit).filter {
                removed.contains(SimUnits.parse($0).key)
            }
            for key in removed { macs[mac]!.defaults[key] = nil }
            for (unit, value) in set { SimUnits.set(unit, to: value, in: &macs[mac]!.defaults) }
            // An import is a user change of every atom it sets and a user delete of every importable key it removes.
            for unit in removedUnits { groundTruth.recordUserChange(mac: mac, unit: unit, tokens: [], time: clock.now) }
            for (unit, value) in set {
                groundTruth.recordUserChange(mac: mac, unit: unit, tokens: value.tokens, time: clock.now)
            }
            let command = SimUserCommand.importFile(set: setUnits, removed: removed)
            runHook(mac, .command) { brain, context in brain.userCommand(command, &context) }
        case .setHotkey(let mac, let action, let combo):
            let unit = "Hotkeys/\(action)"
            let token = mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) {
                SimUnits.set(unit, to: .dictionary(["combo": .int(combo), "token": token]), in: &$0)
            }
        case .chooseItemIcon(let mac, let item):
            let unit = "ItemIcons/\(item)"
            let token = mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: token, in: &$0) }
        case .oversizeIcon(let mac):
            let token = mintUserToken(unit: "IceIcon")
            guard case .string(let text) = token else { return }
            let padding = String(repeating: "x", count: (1 << 20) + 4096)
            let json = "{\"token\":\"\(text)\",\"pad\":\"\(padding)\"}"
            change(mac, origin: .user, units: ["IceIcon"]) { $0["IceIcon"] = .data(Data(json.utf8)) }
        case .moveApp27(let mac, let bundle, let section):
            guard macs[mac]?.generation == 27 else { return }
            let unit = "l27/\(bundle)"
            // In the defaults a visible application has no entry (D-04): moving one back to the visible section removes its entry, and
            // moving it to the section it is in changes nothing.
            let current = Self.sections27(in: macs[mac]!.defaults)[bundle] ?? .int(0)
            guard current != .int(section) else { return }
            if section == 0 {
                change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: nil, in: &$0) }
            } else {
                let token = mintUserToken(unit: unit)
                change(mac, origin: .user, units: [unit]) {
                    SimUnits.set(unit, to: .dictionary(["section": .int(section), "token": token]), in: &$0)
                }
            }
        case .applyProfile(let mac, let profile, let byUser):
            applyProfile(profile, on: mac, byUser: byUser)
        case .saveProfile(let mac, let profile):
            guard macs[mac]?.generation == 27 else { return }
            let unit = "prof/\(profile)"
            let token = mintUserToken(unit: unit)
            let sections = Self.sections27(in: macs[mac]!.defaults)
            change(mac, origin: .user, units: [unit]) {
                SimUnits.set(
                    unit,
                    to: .dictionary(["name": .string(profile), "sections27": .dictionary(sections), "token": token]),
                    in: &$0
                )
            }
        case .renameProfile(let mac, let profile):
            guard macs[mac]?.generation == 27,
                  case .dictionary(var entries)? = SimUnits.value(of: "prof/\(profile)", in: macs[mac]!.defaults)
            else { return }
            let unit = "prof/\(profile)"
            entries["name"] = .string("\(profile)-renamed")
            entries["token"] = mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: .dictionary(entries), in: &$0) }
        case .deleteProfile(let mac, let profile):
            // Only a Mac of macOS 27 has profiles of the macOS 27 family, and only a profile that exists can be deleted.
            let unit = "prof/\(profile)"
            guard macs[mac]?.generation == 27, let defaults = macs[mac]?.defaults, SimUnits.value(of: unit, in: defaults) != nil else { return }
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: nil, in: &$0) }
        default:
            break
        }
    }

    /// The section of every macOS 27 app in the defaults.
    private static func sections27(in defaults: [String: SimValue]) -> [String: SimValue] {
        var result: [String: SimValue] = [:]
        if case .dictionary(let entries)? = defaults["MacOS27Layout"] {
            for (bundle, value) in entries {
                if case .dictionary(let fields) = value, let section = fields["section"] { result[bundle] = section }
            }
        }
        return result
    }

    private func applyProfile(_ profile: String, on mac: SimMacName, byUser: Bool) {
        guard macs[mac]?.generation == 27,
              case .dictionary(let entries)? = SimUnits.value(of: "prof/\(profile)", in: macs[mac]!.defaults),
              case .dictionary(let target)? = entries["sections27"]
        else { return }
        let current = Self.sections27(in: macs[mac]!.defaults)
        var changed: [String] = []
        var newValues: [(String, SimValue?)] = []
        for bundle in target.keys.sorted() where (current[bundle] ?? .int(0)) != target[bundle] {
            let unit = "l27/\(bundle)"
            // A profile bound to a Space or display is an automatic store, and an automatic store never
            // overwrites an entry the user made (D-04).
            if !byUser, let held = SimUnits.value(of: unit, in: macs[mac]!.defaults), held.tokens.contains(where: { groundTruth.origin(of: $0) == .user }) {
                continue
            }
            if target[bundle] == .int(0) {
                // A visible application has no entry in the defaults (D-04).
                newValues.append((unit, nil))
            } else {
                let token = byUser ? mintUserToken(unit: unit) : mintAutoToken(mac: mac)
                newValues.append((unit, .dictionary(["section": target[bundle]!, "token": token])))
            }
            changed.append(unit)
        }
        guard !changed.isEmpty else { return }
        change(mac, origin: byUser ? .user : .automatic, units: changed) { defaults in
            for (unit, value) in newValues { SimUnits.set(unit, to: value, in: &defaults) }
        }
    }

    private func handleAutomatic(_ event: SimEvent) {
        switch event {
        case .autoPlace(let mac, let unit):
            let token = mintAutoToken(mac: mac)
            change(mac, origin: .automatic, units: [unit]) { SimUnits.set(unit, to: token, in: &$0) }
        case .learn(let mac, let key):
            let token = mintAutoToken(mac: mac)
            change(mac, origin: .automatic, units: [SimUnits.unitName(key: key, entry: nil)]) {
                var elements: [SimValue] = []
                if case .array(let existing)? = $0[key] { elements = existing }
                elements.append(token)
                $0[key] = .array(elements)
            }
        case .setFlag(let mac, let key):
            change(mac, origin: .automatic, units: [key]) { $0[key] = .bool(true) }
        case .seed27(let mac):
            guard macs[mac]?.generation == 27 else { return }
            var added: [(String, SimValue)] = []
            for bundle in SimKeys.apps27 where SimUnits.value(of: "l27/\(bundle)", in: macs[mac]!.defaults) == nil {
                added.append(("l27/\(bundle)", .dictionary(["section": .int(0), "token": mintAutoToken(mac: mac)])))
            }
            guard !added.isEmpty else { return }
            change(mac, origin: .automatic, units: added.map(\.0)) { defaults in
                for (unit, value) in added { SimUnits.set(unit, to: value, in: &defaults) }
            }
        case .placeNewApp27(let mac, let bundle):
            guard macs[mac]?.generation == 27 else { return }
            let unit = "l27/\(bundle)"
            var known: [SimValue] = []
            if case .array(let existing)? = macs[mac]!.defaults["KnownApplications27"] { known = existing }
            guard !known.contains(.string(bundle)), SimUnits.value(of: unit, in: macs[mac]!.defaults) == nil else { return }
            let token = mintAutoToken(mac: mac)
            known.append(.string(bundle))
            change(mac, origin: .automatic, units: [unit, SimUnits.known27]) { defaults in
                SimUnits.set(unit, to: .dictionary(["section": .int(1), "token": token]), in: &defaults)
                defaults["KnownApplications27"] = .array(known)
            }
        default:
            break
        }
    }

    /// An item changes its stored key: holzBar moves the value from one unit to the other by itself.
    private func rekey(_ mac: SimMacName, from: String, to: String) {
        guard let value = SimUnits.value(of: from, in: macs[mac]?.defaults ?? [:]) else { return }
        change(mac, origin: .automatic, units: [from, to]) {
            SimUnits.set(from, to: nil, in: &$0)
            SimUnits.set(to, to: value, in: &$0)
        }
    }

    // MARK: Ground truth feed

    /// Tells the ground truth about versions the provider made itself (conflict copies, foreign bytes).
    private func registerProviderVersions() {
        for folder in providers.keys.sorted() {
            let provider = providers[folder]!
            let known = registeredVersions[folder] ?? 0
            for id in provider.versions.keys.sorted() where id > known {
                guard let version = provider.versions[id] else { continue }
                switch version.kind {
                case .write:
                    break
                case .conflictCopy(let origin):
                    groundTruth.recordCopy(version: id, of: origin, path: version.path, time: version.writtenAt)
                case .foreign:
                    groundTruth.recordForeign(version: id, path: version.path, time: version.writtenAt)
                }
            }
            registeredVersions[folder] = (provider.versions.keys.max() ?? known)
        }
    }

    /// Everything that holds tokens now: defaults, readable files (decoded by the brains) and pending holdings.
    /// The tokens a file holds, whichever brain can read it. A provider version never changes its bytes, so the answer for
    /// a version is kept (the brains of a Mac may be replaced by an update, and all of them read the same bytes).
    private func tokens(inFile path: String, data: Data, version: Int) -> Set<String> {
        if version > 0, let known = versionTokens[version], known.path == path { return known.tokens }
        var tokens = Set<String>()
        for brainMac in brains.keys.sorted() {
            tokens.formUnion(brains[brainMac]!.heldTokens(inFile: path, data: data))
        }
        if version > 0 { versionTokens[version] = (path, tokens) }
        return tokens
    }

    func holderSnapshot() -> SimHolderSnapshot {
        var snapshot = SimHolderSnapshot()
        for mac in macs.keys.sorted() {
            snapshot.defaults[mac] = SimUnits.tokens(in: macs[mac]!.defaults)
            let pending = brains[mac]?.heldTokens ?? []
            if !pending.isEmpty { snapshot.pending[mac] = pending }
        }
        for folder in providers.keys.sorted() {
            let provider = providers[folder]!
            for mac in provider.replicas.keys.sorted() {
                let replica = provider.replica(of: mac)
                for path in replica.entries.keys.sorted() {
                    guard case .present(let data) = replica.entries[path]! else { continue }
                    let version = replica.versions[path] ?? 0
                    if let kind = provider.version(version)?.kind, case .foreign = kind { continue }
                    let tokens = tokens(inFile: path, data: data, version: version)
                    snapshot.files.append(SimHeldFile(
                        place: "\(folder):\(mac):\(path)", mac: mac, path: path, version: version, tokens: tokens
                    ))
                }
                for path in replica.conflictVersions.keys.sorted() {
                    for conflict in replica.conflictVersions[path] ?? [] {
                        let tokens = tokens(inFile: path, data: conflict.data, version: conflict.version)
                        snapshot.files.append(SimHeldFile(
                            place: "\(folder):\(mac):\(path)#v\(conflict.version)", mac: mac, path: path,
                            version: conflict.version, tokens: tokens
                        ))
                    }
                }
            }
        }
        return snapshot
    }

    // MARK: Observation

    private func snapshots() -> [SimMacName: SimMacSnapshot] {
        var result: [SimMacName: SimMacSnapshot] = [:]
        for mac in macs.keys.sorted() {
            guard let state = macs[mac], let brain = brains[mac] else { continue }
            result[mac] = SimMacSnapshot(
                version: state.version, generation: state.generation, running: state.running, enabled: state.enabled,
                folderID: state.folderID, hint: brain.hint, openPrompt: brain.openPrompt, heldTokens: brain.heldTokens,
                defaultsTokens: SimUnits.tokens(in: state.defaults),
                report: (brain as? any SimBrainIntrospection)?.report()
            )
        }
        return result
    }

    private func runOracles(_ moment: SimCheckMoment, focus newFocus: SimFocus, event: SimEvent?) {
        let active = oracles.oracles(at: moment)
        guard !active.isEmpty else { return }
        focus = newFocus
        groundTruth.isCachingHolders = true
        defer { groundTruth.isCachingHolders = false }
        for oracle in active {
            guard let found = oracle.check(self, event: event) else { continue }
            if violationKeys.insert("\(found.id)|\(found.description)").inserted { oracleViolations.append(found); violationObserver?(found, self) }
        }
        focus = nil
    }

    /// Every step so far, including the one in progress.
    var allSteps: [SimStepRecord] {
        stepRecords + (currentStep.map { [$0] } ?? [])
    }

    /// Runs the oracles of a moment on demand (the drain and the metamorphic runners use it).
    func runOracles(_ moment: SimCheckMoment, event: SimEvent? = nil) {
        let active = oracles.oracles(at: moment)
        groundTruth.isCachingHolders = true
        defer { groundTruth.isCachingHolders = false }
        for oracle in active {
            guard let found = oracle.check(self, event: event) else { continue }
            if violationKeys.insert("\(found.id)|\(found.description)").inserted { oracleViolations.append(found); violationObserver?(found, self) }
        }
    }

    /// Records a violation found outside the per-step oracles (the drain and the metamorphic runners).
    func report(_ found: SimViolation) {
        if violationKeys.insert("\(found.id)|\(found.description)").inserted { oracleViolations.append(found); violationObserver?(found, self) }
    }

    /// Adds a Mac after the start (a fresh Mac joining after a drain, INV-C6).
    func addMac(_ spec: SimMacSpec) {
        let name = spec.name
        guard macs[name] == nil else { return }
        var state = SimMacState(
            name: name,
            version: spec.version,
            markers: SimIdentityMarkers(mac: name),
            uid: 501,
            generation: spec.generation,
            random: random.fork("mac-\(name.name)")
        )
        state.defaults = spec.defaults
        state.enabled = spec.enabled && spec.folder != nil
        state.folderID = spec.folder
        macs[name] = state
        groundTruth.setGeneration(spec.generation, of: name)
        brains[name] = brainFactory(spec.version, name)
        clock.setOffset(spec.clockOffsetMilliseconds, of: name)
        if let folder = spec.folder ?? spec.syncedFolder { ensureReplica(of: name, in: folder) }
        if spec.running { step(.launch(mac: name)) }
    }

    /// Asks the provider to download every dataless file on every Mac (the drain assumes they become readable).
    /// The provider stops failing: every share is mounted, no Mac hangs or is offline, and no file shows a partial copy any more. The
    /// quiet phase of an exploration starts from here (A2 section 5.6, Q1 to Q3: from T0 on there are no provider faults), so that a
    /// share that was unmounted or hung at the end of the random phase does not keep a Mac from the agreement the drain checks.
    func healProviders() {
        for folder in providers.keys.sorted() {
            for mac in providers[folder]!.replicas.keys.sorted() {
                providers[folder]!.mount(mac)
                providers[folder]!.stall(mac: mac, until: 0)
                providers[folder]!.setOffline(mac, until: 0)
            }
            providers[folder]!.settle(at: clock.now)
        }
        flushProviderLogs()
    }

    func materializeDatalessFiles() {
        for folder in providers.keys.sorted() {
            for mac in providers[folder]!.replicas.keys.sorted() {
                let replica = providers[folder]!.replica(of: mac)
                for path in replica.entries.keys.sorted() {
                    if case .dataless = replica.entries[path]! { providers[folder]!.requestDownload(path: path, mac: mac) }
                }
            }
        }
        flushProviderLogs()
    }

    /// The global time of the next delivery or timer, if any.
    var nextDueTime: Int64? {
        var due: Int64?
        for provider in providers.values {
            if let next = provider.nextDeliveryTime { due = min(due ?? next, next) }
        }
        if let next = timers.map(\.time).min() { due = min(due ?? next, next) }
        return due
    }

    /// True while the provider still has deliveries queued.
    var hasPendingDeliveries: Bool {
        providers.values.contains { $0.nextDeliveryTime != nil } || !timers.isEmpty
    }

    /// A digest of the world state without its history, for visited-state pruning in the exhaustive runner.
    var stateDigest: String {
        var lines: [String] = ["now=\(clock.now)"]
        for mac in macs.keys.sorted() {
            let state = macs[mac]!
            lines.append("mac \(mac) run=\(state.running) en=\(state.enabled) f=\(state.folderID ?? "-") v=\(state.version.rawValue) g=\(state.generation)")
            lines.append("defaults \(mac) \(SimValue.dictionary(state.defaults).canonical)")
            lines.append("held \(mac) \(brains[mac]!.heldTokens.sorted()) \(brains[mac]!.openPrompt?.shown.count ?? -1) \(brains[mac]!.hint ?? "-")")
            lines.append("offset \(mac) \(clock.offset(of: mac))")
        }
        for folder in providers.keys.sorted() {
            let provider = providers[folder]!
            for mac in provider.replicas.keys.sorted() {
                let replica = provider.replica(of: mac)
                for path in replica.entries.keys.sorted() {
                    lines.append("entry \(folder) \(mac) \(path) \(replica.versions[path] ?? 0) \(replica.isMounted)")
                }
            }
            for item in provider.queue.sorted(by: { ($0.time, $0.sequence) < ($1.time, $1.sequence) }) {
                lines.append("queue \(folder) \(item.time - clock.now) \(item.target) \(item.path) \(item.version) \(item.mode)")
            }
        }
        for timer in timers.sorted(by: { ($0.time, $0.sequence) < ($1.time, $1.sequence) }) {
            lines.append("timer \(timer.mac) \(timer.tag) \(timer.time - clock.now)")
        }
        return SimDigest.hex(of: lines.joined(separator: "\n"))
    }

    // MARK: Provider events

    private func handleProvider(_ event: SimProviderEvent) {
        func provider(_ folder: String) {
            if providers[folder] == nil { providers[folder] = makeProvider(folder: folder) }
            providers[folder]!.now = clock.now
        }
        switch event {
        case .restore(let folder, let path, let version):
            provider(folder)
            providers[folder]!.restore(path: path, version: version)
        case .delete(let folder, let path):
            provider(folder)
            providers[folder]!.delete(path: path)
        case .deleteFolder(let folder):
            provider(folder)
            providers[folder]!.deleteFolder()
        case .evict(let folder, let path, let mac):
            provider(folder)
            providers[folder]!.evict(path: path, mac: mac)
        case .exposePartial(let folder, let path, let mac, let duration):
            provider(folder)
            providers[folder]!.exposePartial(path: path, mac: mac, until: clock.now + max(0, duration))
        case .stall(let folder, let mac, let duration):
            provider(folder)
            providers[folder]!.stall(mac: mac, until: duration.map { clock.now + max(0, $0) } ?? Int64.max)
        case .unmount(let folder, let mac):
            provider(folder)
            providers[folder]!.unmount(mac)
        case .mount(let folder, let mac):
            provider(folder)
            providers[folder]!.mount(mac)
        case .foreign(let folder, let path, let kind):
            provider(folder)
            providers[folder]!.foreign(path: path, kind: kind)
        case .plant(let folder, let path, let data):
            provider(folder)
            providers[folder]!.plant(path: path, data: data)
        case .offline(let folder, let mac, let duration):
            provider(folder)
            providers[folder]!.setOffline(mac, until: clock.now + max(0, duration))
        }
        registerProviderVersions()
    }
}
