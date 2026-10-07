//
//  SimMacRedesign.swift
//  holzBar
//

import Foundation
@testable import HolzBarCore

/// The unit table the simulator's redesigned Mac uses: permissive whole units and one split
/// family, so the engine's behavior is judged apart from the unit rules of the app.
enum SimEngineUnits {
    /// The whole units, named like the simulator's settings keys.
    static let wholeUnits = ["S1", "S2", "S3", "S4", "S5", "S6"]
    /// The split family; the simulator calls its units `Hotkeys/<item>`.
    static let family = "Hk"
    private static let simFamilyKey = "Hotkeys"

    static func table(wholeUnits: [String] = SimEngineUnits.wholeUnits) -> SyncUnitTable {
        var descriptors = wholeUnits.map { descriptor($0, isFamily: false) }
        descriptors.append(descriptor(family, isFamily: true))
        return SyncUnitTable(version: 1, descriptors: descriptors)
    }

    private static func descriptor(_ name: String, isFamily: Bool) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [],
            cap: 1 << 10,
            maximumItems: isFamily ? SyncDeviceFile.maximumEntriesPerFamily : nil,
            scope: nil,
            isSet: false,
            isFamily: isFamily,
            measure: { $0.encodedSize },
            validate: { _, _ in true }
        )
    }

    /// The engine's key for a simulator unit name, or `nil` for a unit the table does not hold.
    static func key(ofUnit unit: String) -> SyncUnitKey? {
        guard let slash = unit.firstIndex(of: "/") else {
            return .whole(unit)
        }
        guard unit[..<slash] == simFamilyKey else {
            return nil
        }
        return .split(family: family, item: String(unit[unit.index(after: slash)...]))
    }

    /// The simulator's unit name for an engine key.
    static func unit(of key: SyncUnitKey) -> String {
        switch key {
        case .whole(let name):
            name
        case .split(_, let item):
            "\(simFamilyKey)/\(item)"
        }
    }
}

extension SyncValue {
    /// The engine's value for a simulator value.
    init?(sim value: SimValue) {
        self.init(propertyList: value.propertyList)
    }
}

extension SimValue {
    /// The simulator's value for an engine value, `nil` for a kind the simulator has no case for.
    init?(sync value: SyncValue) {
        self.init(propertyList: value.propertyList)
    }
}

/// A simulated Mac that runs the real ``SyncEngine``. It feeds events in, executes the effects
/// the engine returns strictly in order, and answers the oracles' questions about files and about
/// itself. Everything is deterministic: the clock is the Mac's wall clock, the randomness is the
/// Mac's own stream and the I/O is ``SimFolderIO`` on the simulated folder.
///
/// The engine state lives in the Mac's Sigma blob. Plan 28-08 replaces the bootstrap this
/// adapter does at its first launch (a Sigma that already belongs to a group, enabled, with an
/// empty replica) with the real launch and join events.
struct SimMacRedesign: SimSyncBrain, SimBrainIntrospection {
    static let counterMirrorKey = "SettingsSyncCounter"
    static let generationKey = "SettingsSyncGeneration"

    var kind: SimMacVersion { .redesign }

    /// The defenses the engine runs with; a control engine removes one.
    var guards = SyncGuards.all
    let table: SyncUnitTable

    /// Whether launch applies the fast-forwards that wait, as the app does at launch from the
    /// persisted replica (analysis section 4.6.6, step 8). Until plan 28-08 adds the launch event
    /// to the engine, the adapter does it with the restart command and keeps the relaunch back.
    var appliesAtLaunch = true

    /// The engine state while the app runs; `nil` while it does not.
    private var live: SyncState?
    private var ignoresRelaunch = false
    private var pendingFresh: SyncFreshIdentity?
    /// Which tokens each dot carried, for the oracles' questions. It is bookkeeping of the test
    /// harness, not engine memory, so it outlives a crash.
    private var dotTokens: [SyncDot: Set<String>] = [:]
    private var cachedHeld: Set<String> = []
    private var cachedView = SyncView(hint: nil, lines: [])
    private var cachedReport = SimBrainReport()

    init(table: SyncUnitTable = SimEngineUnits.table(), guards: SyncGuards = .all) {
        self.table = table
        self.guards = guards
    }

    // MARK: Hooks

    mutating func launch(_ context: inout SimMacContext) {
        live = nil
        guard context.enabled, context.folderID != nil else {
            return
        }
        ensureLive(&context)
        run(.defaultsChanged(snapshot(context)), &context)
        run(.timer(.periodic), &context)
        if appliesAtLaunch {
            ignoresRelaunch = true
            run(.command(.restart), &context)
            ignoresRelaunch = false
        }
    }

    mutating func quit(_ context: inout SimMacContext) {
        guard live != nil else {
            return
        }
        run(.quit(snapshot(context)), &context)
        live = nil
    }

    mutating func processDied() {
        live = nil
    }

    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        run(.defaultsChanged(snapshot(context)), &context)
    }

    mutating func folderSignal(_ context: inout SimMacContext) {
        guard live != nil else {
            return
        }
        execute(.schedule(.check, after: SyncTimer.check.delay), &context)
    }

    mutating func timerFired(tag: String, _ context: inout SimMacContext) {
        guard let timer = Self.timer(forTag: tag) else {
            return
        }
        run(.timer(timer), &context)
    }

    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        switch command {
        case .turnOn(let folder), .changeFolder(let folder):
            context.enabled = true
            context.folderID = folder
            ensureLive(&context)
            live?.isEnabled = true
            run(.defaultsChanged(snapshot(context)), &context)
            run(.timer(.periodic), &context)
        case .turnOff:
            context.enabled = false
            for timer in Self.allTimers {
                context.cancelTimer(tag: Self.tag(of: timer))
            }
            if var state = live {
                state.isEnabled = false
                live = state
                store(state, &context)
            }
        case .restart:
            run(.command(.restart), &context)
        case .importFile:
            run(.defaultsChanged(snapshot(context)), &context)
        case .answer:
            break
        }
    }

    var hint: String? {
        switch cachedView.hint {
        case .restart?:
            "Settings changed on another Mac"
        case .choose?, .chooseAfterJoin?:
            "Choose Settings"
        case nil:
            nil
        }
    }

    var heldTokens: Set<String> { cachedHeld }

    // MARK: Running the engine

    private mutating func run(_ event: SyncEvent, _ context: inout SimMacContext) {
        guard let state = live else {
            return
        }
        if pendingFresh == nil {
            pendingFresh = Self.freshIdentity(&context)
        }
        let step = SyncEngine.handle(event, state: state, environment: environment(context))
        live = step.state
        if let fresh = pendingFresh, step.state.mac == fresh.mac {
            pendingFresh = nil
        }
        learn(step.state)
        for effect in step.effects {
            execute(effect, &context)
        }
        refresh(context)
    }

    private mutating func execute(_ effect: SyncEffect, _ context: inout SimMacContext) {
        switch effect {
        case .applyUnits(let changes):
            for key in changes.keys.sorted() {
                var value: SimValue?
                if case .value(let synced)? = changes[key] {
                    value = SimValue(sync: synced)
                }
                SimUnits.set(SimEngineUnits.unit(of: key), to: value, in: &context.defaults)
            }
        case .persist(let persist):
            // The order of analysis section 4.4: the generation and the counter mirror first,
            // then Sigma.
            context.defaults[Self.generationKey] = .int(Int(clamping: persist.generation))
            context.defaults[Self.counterMirrorKey] = .int(Int(clamping: persist.counter))
            context.caches = Data(String(max(persist.counter, Self.highWater(context))).utf8)
            if let state = live {
                store(state, &context)
            }
        case .readFolder(let request):
            let result = SimFolderIO.read(request, &context)
            for version in newVersions(in: result) {
                context.reportIngest(version: version)
            }
            run(.folderRead(result.read, purpose: request.purpose), &context)
        case .writeOwnFile(let request):
            let result = SimFolderIO.write(request, &context)
            run(.writeFinished(result), &context)
        case .schedule(.periodic, _):
            // The simulator's drain runs until no timer is left, so a poll that reschedules
            // itself would never let it finish; a launch reads the folder, and so does a signal.
            break
        case .schedule(let timer, let after):
            // A timer replaces a pending one of the same kind.
            context.cancelTimer(tag: Self.tag(of: timer))
            context.scheduleTimer(afterMilliseconds: Int64((after * 1000).rounded()), tag: Self.tag(of: timer))
        case .cancelTimer(let timer):
            context.cancelTimer(tag: Self.tag(of: timer))
        case .relaunch:
            if !ignoresRelaunch {
                context.requestRelaunch()
            }
        case .requestDownload(let macs):
            for mac in macs {
                context.requestDownload(SimFolderIO.path(of: mac))
            }
        }
    }

    /// Reports the versions this read gives the Mac something new: the ones whose join changes the
    /// replica. A version the replica already holds is dominated, and the Mac does nothing with it.
    private func newVersions(in result: SimFolderReadResult) -> [Int] {
        guard let state = live else {
            return []
        }
        var versions: [Int] = []
        for file in result.read.files {
            guard case .contents(let contents) = file.state, let mac = file.macID, let version = result.versions[mac] else {
                continue
            }
            if SyncReplica.join(state.replica, contents.replica).replica != state.replica {
                versions.append(version)
            }
        }
        return versions
    }

    private func environment(_ context: SimMacContext) -> SyncEnvironment {
        var mirror: UInt64 = 0
        if case .int(let number)? = context.defaults[Self.counterMirrorKey] {
            mirror = UInt64(max(0, number))
        }
        return SyncEnvironment(
            table: table,
            generation: context.environment.generation == 27 ? .g27 : .g26,
            now: context.wallClock,
            unixSeconds: UInt64(max(0, context.wallClock.timeIntervalSince1970)),
            counterFloors: SyncCounterFloors(mirror: mirror, highWater: Self.highWater(context)),
            guards: guards,
            freshIdentity: pendingFresh
        )
    }

    private static func highWater(_ context: SimMacContext) -> UInt64 {
        context.caches.flatMap { String(data: $0, encoding: .utf8) }.flatMap { UInt64($0) } ?? 0
    }

    // MARK: State

    /// The engine state of this Mac: Sigma if it holds one, else a new one that already belongs
    /// to a group.
    private mutating func ensureLive(_ context: inout SimMacContext) {
        if live != nil {
            return
        }
        var state: SyncState
        if let data = context.sigma, case .state(let decoded) = SyncStateCodec.decode(data) {
            state = decoded
        } else {
            let fresh = Self.freshIdentity(&context)
            state = SyncState(mac: fresh.mac, nonce: fresh.nonce, isEnabled: true)
            // Every whole unit starts with the value this Mac holds as its baseline: nothing in
            // it is a change of the user's.
            let current = snapshot(context)
            for key in table.wholeKeys {
                state.baseline[key] = current.values[key]?.digest ?? .unset
            }
            store(state, &context)
        }
        state.isEnabled = context.enabled
        live = state
        learn(state)
        refresh(context)
    }

    private func store(_ state: SyncState, _ context: inout SimMacContext) {
        context.sigma = try? SyncStateCodec.encode(state)
    }

    private func snapshot(_ context: SimMacContext) -> SyncSnapshot {
        var values: [SyncUnitKey: SyncValue] = [:]
        for (unit, value) in SimUnits.units(of: context.defaults) {
            guard let key = SimEngineUnits.key(ofUnit: unit), table.descriptor(for: key) != nil else {
                continue
            }
            values[key] = SyncValue(sim: value) ?? SyncProjection.unrepresentable
        }
        return SyncSnapshot(values: values)
    }

    private static func freshIdentity(_ context: inout SimMacContext) -> SyncFreshIdentity {
        var bytes = [UInt8]()
        for _ in 0..<2 {
            var word = context.random.next()
            for _ in 0..<8 {
                bytes.append(UInt8(truncatingIfNeeded: word))
                word >>= 8
            }
        }
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        let nonce = String(context.random.next(), radix: 16, uppercase: true)
        return SyncFreshIdentity(mac: SyncMacID(uuid), nonce: nonce)
    }

    // MARK: Timers

    private static let allTimers: [SyncTimer] = [.capture, .relay, .check, .periodic, .healing]

    static func tag(of timer: SyncTimer) -> String {
        switch timer {
        case .capture: "capture"
        case .relay: "relay"
        case .check: "check"
        case .periodic: "periodic"
        case .healing: "healing"
        }
    }

    private static func timer(forTag tag: String) -> SyncTimer? {
        allTimers.first { self.tag(of: $0) == tag }
    }

    // MARK: Bookkeeping for the oracles

    /// Remembers the token every live entry carries, by dot.
    private mutating func learn(_ state: SyncState) {
        for key in state.replica.keys {
            for entry in state.replica.live(key) {
                dotTokens[entry.dot, default: []].formUnion(Self.tokens(of: entry))
            }
        }
    }

    private static func tokens(of entry: SyncEntry) -> Set<String> {
        guard let value = entry.value, let sim = SimValue(sync: value) else {
            return []
        }
        return Set(sim.tokens)
    }

    private mutating func refresh(_ context: SimMacContext) {
        guard let state = live else {
            return
        }
        let environment = environment(context)
        cachedView = SyncEngine.view(of: state, environment: environment)
        var held = Set<String>()
        var applied = Set<String>()
        var waiting = Set<String>()
        let appliedDots = Set(state.applied.values.flatMap { $0 })
        for key in state.replica.keys {
            for entry in state.replica.live(key) {
                let tokens = Self.tokens(of: entry)
                held.formUnion(tokens)
                if appliedDots.contains(entry.dot) {
                    applied.formUnion(tokens)
                } else {
                    waiting.formUnion(tokens)
                }
            }
        }
        cachedHeld = held
        var report = SimBrainReport()
        report.deviceID = state.mac.rawValue
        report.ownFilePath = SimFolderIO.path(of: state.mac)
        report.joining = state.pendingJoin != nil
        report.ownCounter = Int(clamping: state.counter)
        // The oracles' menu hint is the Choose Settings hint: a bystander gets none (INV-P7). A
        // Restart hint is shown in the menu too, but it is no question.
        report.menuHint = cachedView.hint == .choose || cachedView.hint == .chooseAfterJoin
        report.sizeWarning = state.session.isTooLargeToPublish
        report.sigmaBytes = (try? SyncStateCodec.encode(state).count) ?? 0
        report.devicesSeen = state.replica.context.macs.count
        report.appliedTokens = applied
        report.waitingTokens = waiting
        cachedReport = report
    }

    // MARK: SimBrainIntrospection

    func report() -> SimBrainReport { cachedReport }

    private static func contents(path: String, data: Data) -> SyncDeviceFile.Contents? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard case .success(let contents) = SyncDeviceFile.decode(data, fileName: name) else {
            return nil
        }
        return contents
    }

    func heldTokens(inFile path: String, data: Data) -> Set<String> {
        guard let contents = Self.contents(path: path, data: data) else {
            return []
        }
        var tokens = Set<String>()
        for key in contents.replica.keys {
            for entry in contents.replica.live(key) {
                tokens.formUnion(Self.tokens(of: entry))
            }
        }
        return tokens
    }

    func claimedPast(ofFile path: String, data: Data) -> Set<String>? {
        guard let contents = Self.contents(path: path, data: data) else {
            return nil
        }
        var claimed = Set<String>()
        for (dot, tokens) in dotTokens where contents.replica.context.covers(dot) {
            claimed.formUnion(tokens)
        }
        return claimed
    }

    func deletedUnits(inFile path: String, data: Data) -> Set<String>? {
        guard let contents = Self.contents(path: path, data: data) else {
            return nil
        }
        var units = Set<String>()
        for key in contents.replica.keys where contents.replica.live(key).contains(where: { $0.payload == .deleted }) {
            units.insert(SimEngineUnits.unit(of: key))
        }
        return units
    }

    func mentionedUnits(inFile path: String, data: Data) -> Set<String>? {
        Self.contents(path: path, data: data).map { Set($0.replica.keys.map(SimEngineUnits.unit(of:))) }
    }

    func writerID(inFile path: String, data: Data) -> String? {
        Self.contents(path: path, data: data)?.mac.rawValue
    }

    func claimedCounter(ofDevice device: String, inFile path: String, data: Data) -> Int? {
        guard let contents = Self.contents(path: path, data: data), let mac = SyncMacID(device) else {
            return nil
        }
        return Int(clamping: contents.replica.context[mac])
    }
}

extension SyncUnitTable {
    /// The whole units of the table, for tests that build a state.
    var wholeKeys: [SyncUnitKey] {
        SimEngineUnits.wholeUnits.map { SyncUnitKey.whole($0) }.filter { descriptor(for: $0) != nil }
    }
}
