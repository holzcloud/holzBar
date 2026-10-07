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

    init(
        _ name: SimMacName,
        _ version: SimMacVersion,
        generation: Int = 26,
        enabled: Bool = true,
        folder: String? = "F1",
        running: Bool = false,
        defaults: [String: SimValue] = [:],
        clockOffsetMilliseconds: Int64 = 0
    ) {
        self.name = name
        self.version = version
        self.generation = generation
        self.enabled = enabled
        self.folder = folder
        self.running = running
        self.defaults = defaults
        self.clockOffsetMilliseconds = clockOffsetMilliseconds
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
        case .beta2, .redesign, .redesignSkew: SimInertBrain(kind: version)
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
    /// The longest a coordinated call blocks before the caller gives up.
    var ioTimeoutMilliseconds: Int64 = 5_000

    private let brainFactory: BrainFactory
    private var timers: [SimTimer] = []
    private var timerSequence = 0
    private var userTokenCounter = 0
    private var autoTokenCounter = 0
    private var backups: [SimMacName: SimMacBackup] = [:]

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
    }

    init(seed: UInt64, macs specs: [SimMacSpec], brainFactory: BrainFactory? = nil) {
        self.seed = seed
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
            state.defaults = spec.defaults
            state.enabled = spec.enabled && spec.folder != nil
            state.folderID = spec.folder
            macs[name] = state
            brains[name] = self.brainFactory(spec.version, name)
            clock.setOffset(spec.clockOffsetMilliseconds, of: name)
            if let folder = spec.folder { ensureReplica(of: name, in: folder) }
        }
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

    /// SHA-256 over the canonical text of every event and write, in order.
    var traceHash: String { SimDigest.hex(of: trace.joined(separator: "\n")) }

    // MARK: Stepping

    /// Runs one event.
    func step(_ event: SimEvent) {
        record("E \(event.canonical)")
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
        case .clone, .copyAccount, .restorePrefs, .restoreSigma, .restoreHome, .sigmaLost, .reinstall:
            handleIdentity(event)
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
            moveClock(to: at)
            for folder in providers.keys.sorted() {
                guard let providerDue = providers[folder]!.nextDeliveryTime, providerDue <= at else { continue }
                let notices = providers[folder]!.deliverDue(until: at)
                flushProviderLog(folder)
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
            runHook(notice.mac) { brain, context in brain.folderSignal(&context) }
        }
    }

    private func fire(mac: SimMacName, tag: String) {
        guard macs[mac]?.running == true else { return }
        runHook(mac) { brain, context in brain.timerFired(tag: tag, &context) }
    }

    // MARK: Hooks

    /// Runs a hook against a Mac's brain with a fresh context and carries out what it recorded.
    @discardableResult
    private func runHook(_ mac: SimMacName, _ body: (inout any SimSyncBrain, inout SimMacContext) -> Void) -> Bool {
        guard var state = macs[mac], var brain = brains[mac] else { return false }
        let replica: SimFolderReplica
        if let folder = state.folderID {
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
        body(&brain, &context)
        brains[mac] = brain
        state.defaults = context.defaults
        state.sigma = context.sigma
        state.caches = context.caches
        state.random = context.random
        state.enabled = context.enabled
        state.folderID = context.folderID
        macs[mac] = state
        if let folder = state.folderID { ensureReplica(of: mac, in: folder) }
        process(context.actions, of: mac)
        return true
    }

    private func process(_ actions: [SimMacAction], of mac: SimMacName) {
        var relaunch = false
        for action in actions {
            switch action {
            case .write(let folder, let path, let data):
                ensureReplica(of: mac, in: folder)
                providers[folder]!.now = clock.now
                let outcome = providers[folder]!.write(from: mac, path: path, data: data)
                flushProviderLog(folder)
                if case .written(let version) = outcome {
                    record("W \(mac) \(folder) \(path) v\(version) \(SimDigest.canonicalRendering(of: data))")
                } else {
                    record("W! \(mac) \(folder) \(path) \(outcome)")
                }
            case .ingest(let version):
                record("I \(mac) v\(version)")
            case .promptShown(let prompt):
                record("Q \(mac) #\(prompt.id) \(prompt.title) \(prompt.shown.count)")
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
                record("AUTO \(mac) \(unit)")
            case .relaunch:
                relaunch = true
            case .note(let text):
                record("N \(mac) \(text)")
            }
        }
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
        providers[folder]!.ensureReplica(for: mac)
    }

    private func makeProvider(folder: String) -> SimProvider {
        SimProvider()
    }

    // MARK: Lifecycle

    private func launch(_ mac: SimMacName) {
        guard var state = macs[mac], !state.running else { return }
        backups[mac] = SimMacBackup(
            defaults: state.defaults, sigma: state.sigma, caches: state.caches,
            enabled: state.enabled, folderID: state.folderID
        )
        state.running = true
        macs[mac] = state
        runHook(mac) { brain, context in brain.launch(&context) }
    }

    private func quit(_ mac: SimMacName) {
        guard macs[mac]?.running == true else { return }
        runHook(mac) { brain, context in brain.quit(&context) }
        macs[mac]?.running = false
        timers.removeAll { $0.mac == mac }
    }

    /// The process dies without running quit code.
    private func die(_ mac: SimMacName) {
        guard macs[mac] != nil else { return }
        macs[mac]?.running = false
        brains[mac]?.processDied()
        timers.removeAll { $0.mac == mac }
    }

    private func update(_ mac: SimMacName, to version: SimMacVersion) {
        guard macs[mac] != nil else { return }
        quit(mac)
        macs[mac]?.version = version
        brains[mac] = brainFactory(version, mac)
    }

    private func handleIdentity(_ event: SimEvent) {
        switch event {
        case .clone(let from, let to):
            guard let source = macs[from], macs[to] != nil, from != to else { return }
            die(to)
            macs[to]?.defaults = source.defaults
            macs[to]?.sigma = source.sigma
            macs[to]?.caches = source.caches
            macs[to]?.enabled = source.enabled
            macs[to]?.folderID = source.folderID
            if let folder = source.folderID { ensureReplica(of: to, in: folder) }
        case .copyAccount(let from, let to):
            guard let source = macs[from], macs[to] != nil, from != to else { return }
            die(to)
            macs[to]?.defaults = source.defaults
            macs[to]?.sigma = source.sigma
            macs[to]?.caches = source.caches
            macs[to]?.enabled = source.enabled
            macs[to]?.folderID = source.folderID
            macs[to]?.markers.hardwareID = source.markers.hardwareID
            if let folder = source.folderID { ensureReplica(of: to, in: folder) }
        case .restorePrefs(let mac):
            guard let backup = backups[mac], macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.defaults = backup.defaults
            macs[mac]?.sigma = backup.sigma
            macs[mac]?.enabled = backup.enabled
            macs[mac]?.folderID = backup.folderID
        case .restoreSigma(let mac):
            guard let backup = backups[mac], macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.sigma = backup.sigma
        case .restoreHome(let mac, let keepCaches):
            guard let backup = backups[mac], macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.defaults = backup.defaults
            macs[mac]?.sigma = backup.sigma
            macs[mac]?.enabled = backup.enabled
            macs[mac]?.folderID = backup.folderID
            if !keepCaches { macs[mac]?.caches = nil }
        case .sigmaLost(let mac):
            guard macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.sigma = nil
        case .reinstall(let mac):
            guard macs[mac] != nil else { return }
            die(mac)
            macs[mac]?.defaults = [:]
            macs[mac]?.sigma = nil
            macs[mac]?.caches = nil
            macs[mac]?.enabled = false
            macs[mac]?.folderID = nil
            brains[mac] = brainFactory(macs[mac]!.version, mac)
        default:
            break
        }
    }

    // MARK: User and automatic events

    private func command(_ command: SimUserCommand, on mac: SimMacName) {
        guard macs[mac]?.running == true else { return }
        if case .turnOn(let folder) = command { ensureReplica(of: mac, in: folder) }
        if case .changeFolder(let folder) = command { ensureReplica(of: mac, in: folder) }
        runHook(mac) { brain, context in brain.userCommand(command, &context) }
    }

    private func answerPrompt(_ answer: SimAnswer, on mac: SimMacName) {
        guard macs[mac]?.running == true, brains[mac]?.openPrompt != nil else { return }
        runHook(mac) { brain, context in brain.userCommand(.answer(answer), &context) }
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
        runHook(mac) { brain, context in brain.defaultsChanged(origin: origin, units: units, &context) }
    }

    private func handleUser(_ event: SimEvent) {
        switch event {
        case .userEdit(let mac, let unit, let value):
            let newValue = value ?? mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) { SimUnits.set(unit, to: newValue, in: &$0) }
        case .userDelete(let mac, let unit):
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
            for key in removed { macs[mac]!.defaults[key] = nil }
            for (unit, value) in set { SimUnits.set(unit, to: value, in: &macs[mac]!.defaults) }
            let command = SimUserCommand.importFile(set: setUnits, removed: removed)
            runHook(mac) { brain, context in brain.userCommand(command, &context) }
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
            let token = mintUserToken(unit: unit)
            change(mac, origin: .user, units: [unit]) {
                SimUnits.set(unit, to: .dictionary(["section": .int(section), "token": token]), in: &$0)
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
            let unit = "prof/\(profile)"
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
        var newValues: [(String, SimValue)] = []
        for bundle in target.keys.sorted() where current[bundle] != target[bundle] {
            let unit = "l27/\(bundle)"
            let token = byUser ? mintUserToken(unit: unit) : mintAutoToken(mac: mac)
            newValues.append((unit, .dictionary(["section": target[bundle]!, "token": token])))
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

    // MARK: Provider events

    private func handleProvider(_ event: SimProviderEvent) {
        // The fault operations arrive with the provider fault model.
    }
}
