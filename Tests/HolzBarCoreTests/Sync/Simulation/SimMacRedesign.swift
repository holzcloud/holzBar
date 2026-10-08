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

    /// The simulator's name of the set of known applications (a unit of the world, a set of the engine).
    static let knownUnit = SimUnits.known27

    /// - Parameter scoped: Whether the macOS 27 families belong to generation-27 Macs only. A control engine
    ///   passes `false`: it lets every Mac author and apply them.
    static func table(wholeUnits: [String] = SimEngineUnits.wholeUnits, scoped: Bool = true) -> SyncUnitTable {
        var descriptors = wholeUnits.map { descriptor($0, isFamily: false) }
        descriptors.append(descriptor(family, isFamily: true))
        // The macOS 27 families: authored and applied by generation-27 Macs only.
        let scope: SyncGeneration? = scoped ? .g27 : nil
        descriptors.append(descriptor(SyncUnitTable.layout27Family, isFamily: true, scope: scope))
        descriptors.append(descriptor(SyncUnitTable.profilesFamily, isFamily: true, scope: scope))
        descriptors.append(descriptor(SyncUnitTable.knownApplicationsSet, isFamily: false, scope: scope, isSet: true))
        return SyncUnitTable(version: 1, descriptors: descriptors)
    }

    private static func descriptor(_ name: String, isFamily: Bool, scope: SyncGeneration? = nil, isSet: Bool = false) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [],
            cap: 1 << 10,
            maximumItems: isFamily ? SyncDeviceFile.maximumEntriesPerFamily : nil,
            scope: scope,
            isSet: isSet,
            isFamily: isFamily,
            measure: { $0.encodedSize },
            validate: { _, _ in true }
        )
    }

    /// The engine's key for a simulator unit name, or `nil` for a unit the table does not hold.
    static func key(ofUnit unit: String) -> SyncUnitKey? {
        guard let slash = unit.firstIndex(of: "/") else {
            return unit == knownUnit ? nil : .whole(unit)
        }
        let item = String(unit[unit.index(after: slash)...])
        switch String(unit[..<slash]) {
        case simFamilyKey:
            return .split(family: family, item: item)
        case SyncUnitTable.layout27Family:
            return .split(family: SyncUnitTable.layout27Family, item: item)
        case SyncUnitTable.profilesFamily:
            return .split(family: SyncUnitTable.profilesFamily, item: item)
        default:
            return nil
        }
    }

    /// The simulator's unit name for an engine key.
    static func unit(of key: SyncUnitKey) -> String {
        switch key {
        case .whole(let name):
            return name
        case .split(let family, let item):
            switch family {
            case SyncUnitTable.layout27Family, SyncUnitTable.profilesFamily:
                return "\(family)/\(item)"
            default:
                return "\(simFamilyKey)/\(item)"
            }
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

/// A simulated Mac that runs the real ``SyncEngine``. It does what the app's host does: it reads the
/// preferences and Sigma and feeds the launch in, hands every other event to the engine, and executes
/// the effects the engine returns strictly in order. It opens the sheet when the engine has a question
/// and the hint is showing, and it answers it with the engine's own answer commands. Everything is
/// deterministic: the clock is the Mac's wall clock, the randomness is the Mac's own stream and the
/// I/O is ``SimFolderIO`` on the simulated folder.
///
/// The engine state lives in the Mac's Sigma blob, which the adapter writes only when the engine says
/// `persist`, so a crash between two effects leaves exactly what had been persisted.
struct SimMacRedesign: SimSyncBrain, SimBrainIntrospection {
    static let counterMirrorKey = "SettingsSyncCounter"
    static let generationKey = "SettingsSyncGeneration"
    static let deviceIDKey = "SettingsSyncDeviceID"
    static let deviceHashKey = "SettingsSyncDeviceHash"
    static let deviceSaltKey = "SettingsSyncDeviceSalt"
    static let legacyDeviceIDKey = "SettingsSyncLegacyDeviceID"
    static let lastSyncedKey = "SettingsSyncLastSynced"

    var kind: SimMacVersion { .redesign }

    /// The defenses the engine runs with; a control engine removes one.
    var guards = SyncGuards.all
    let table: SyncUnitTable
    /// A control engine that cannot tell holzBar's own stores from the user's moves: it captures every change of
    /// the macOS 27 families as an intent (decision D-04).
    var automaticStoresAreIntents = false

    /// The engine state while the app runs; `nil` while it does not.
    private var live: SyncState?
    private var pendingFresh: SyncFreshIdentity?
    /// Which tokens each dot carried, for the oracles' questions. It is bookkeeping of the test
    /// harness, not engine memory, so it outlives a crash.
    private var dotTokens: [SyncDot: Set<String>] = [:]
    private var cachedHeld: Set<String> = []
    private var cachedView = SyncView(hint: nil, lines: [])
    private var cachedReport = SimBrainReport()

    // The sheet. It stays as it was shown until it is answered or its question is gone.
    private var question: SyncQuestion?
    private var prompt: SimPrompt?
    /// Survives relaunches so that prompt IDs stay unique per Mac.
    private var promptCounter = 0
    private var promptWasOpenAtStart = false

    // What the hook did, for the oracles.
    private var joinedInHook = false
    private var inLaunch = false
    private var reidentifyReason: String?
    private var lastJoinVersions: [Int] = []
    private var unreadListed: Set<String> = []
    private var refusedListed: Set<String> = []

    init(table: SyncUnitTable = SimEngineUnits.table(), guards: SyncGuards = .all) {
        self.table = table
        self.guards = guards
    }

    // MARK: Hooks

    private mutating func begin(launching: Bool = false) {
        promptWasOpenAtStart = prompt != nil
        joinedInHook = false
        inLaunch = launching
        reidentifyReason = nil
    }

    mutating func launch(_ context: inout SimMacContext) {
        begin(launching: true)
        live = nil
        question = nil
        prompt = nil
        if pendingFresh == nil {
            pendingFresh = Self.freshIdentity(&context)
        }
        let step = SyncEngine.launch(launchInput(context), environment: environment(context))
        perform(step, &context)
    }

    mutating func quit(_ context: inout SimMacContext) {
        begin()
        guard live != nil else {
            return
        }
        run(.quit(snapshot(context)), &context)
        live = nil
        question = nil
        prompt = nil
    }

    mutating func processDied() {
        live = nil
        question = nil
        prompt = nil
    }

    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        begin()
        let before = live?.session.snapshot
        let after = snapshot(context)
        run(.defaultsChanged(after), &context)
        // Only the user's own changes of the macOS 27 families are intents; an automatic store writes the same
        // keys and sends none (decision D-04).
        if origin == .user || automaticStoresAreIntents {
            let intents = Self.intents(from: before, to: after, units: Set(units))
            if !intents.isEmpty {
                run(.intent(.userSet(intents)), &context)
            }
        }
    }

    /// The user's changes of `l27` and `prof` units between two snapshots, as the app would report them.
    /// `units` limits them to the units that were changed; `nil` means every unit that differs.
    private static func intents(from before: SyncSnapshot?, to after: SyncSnapshot, units: Set<String>?) -> [SyncUnitIntent] {
        func values(_ snapshot: SyncSnapshot?, family: String) -> [String: SyncValue] {
            var result: [String: SyncValue] = [:]
            for (key, value) in snapshot?.values ?? [:] {
                guard case .split(let name, let item) = key, name == family else {
                    continue
                }
                if let units, !units.contains(SimEngineUnits.unit(of: key)) {
                    continue
                }
                result[item] = value
            }
            return result
        }
        // A unit that changed is looked at on both sides, even where it is absent on one of them.
        let family27 = SyncUnitTable.layout27Family
        let familyProfiles = SyncUnitTable.profilesFamily
        return SyncLayout27.layoutIntents(old: values(before, family: family27), new: values(after, family: family27))
            + SyncLayout27.profileIntents(old: values(before, family: familyProfiles), new: values(after, family: familyProfiles))
    }

    mutating func folderSignal(_ context: inout SimMacContext) {
        begin()
        guard live != nil else {
            return
        }
        execute(.schedule(.check, after: SyncTimer.check.delay), &context)
    }

    mutating func timerFired(tag: String, _ context: inout SimMacContext) {
        begin()
        guard let timer = Self.timer(forTag: tag) else {
            return
        }
        run(.timer(timer), &context)
    }

    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        begin()
        switch command {
        case .turnOn(let folder):
            run(.command(.turnOn(folder)), &context)
        case .changeFolder(let folder):
            run(.command(.changeFolder(folder)), &context)
        case .turnOff:
            run(.command(.turnOff), &context)
        case .restart:
            run(.command(.restart), &context)
        case .importFile:
            // An import is the user's change of every unit it sets or removes, so its intents go first and
            // the publication that follows carries them.
            let intents = Self.intents(from: live?.session.snapshot, to: snapshot(context), units: nil)
            if !intents.isEmpty {
                run(.intent(.userSet(intents)), &context)
            }
            run(.command(.importFinished(snapshot(context))), &context)
        case .answer(let answer):
            self.answer(answer, &context)
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

    var openPrompt: SimPrompt? { prompt }

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
        perform(step, &context)
    }

    /// Takes the new state, then carries out the effects in the order the engine gave them. A crash the
    /// world asked for stops the Mac between two effects, with only what was persisted by then.
    private mutating func perform(_ step: SyncStep, _ context: inout SimMacContext) {
        if let previous = live {
            learn(previous)
        }
        live = step.state
        if let fresh = pendingFresh, step.state.mac == fresh.mac {
            pendingFresh = nil
        }
        learn(step.state)
        if step.effects.contains(where: { if case .commitFolder = $0 { true } else { false } }) {
            // The join decided on the folder: what it read becomes part of what this Mac has seen.
            for version in lastJoinVersions {
                context.reportMerge(version: version)
            }
            joinedInHook = true
        }
        for effect in step.effects {
            guard !context.crashed else {
                break
            }
            execute(effect, &context)
            if context.effectRun() {
                break
            }
        }
        if context.crashed {
            live = nil
            question = nil
            prompt = nil
            return
        }
        refresh(&context)
    }

    private mutating func execute(_ effect: SyncEffect, _ context: inout SimMacContext) {
        guard !context.crashed else {
            return
        }
        switch effect {
        case .applyUnits(let changes):
            for key in changes.keys.sorted() {
                var value: SimValue?
                if case .value(let synced)? = changes[key] {
                    value = SimValue(sync: synced)
                    // Visible is the absence of a stored section, as in the app's defaults.
                    if case .split(SyncUnitTable.layout27Family, _) = key, synced == SyncLayout27.visible {
                        value = nil
                    }
                }
                SimUnits.set(SimEngineUnits.unit(of: key), to: value, in: &context.defaults)
            }
        case .applyKnownApplications(let applications):
            var known: [SimValue] = []
            if case .array(let existing)? = context.defaults["KnownApplications27"] {
                known = existing
            }
            for application in applications where !known.contains(.string(application)) {
                known.append(.string(application))
            }
            context.defaults["KnownApplications27"] = .array(known)
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
            readFolder(request, &context)
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
            context.requestRelaunch()
        case .requestDownload(let macs):
            for mac in macs {
                context.requestDownload(SimFolderIO.path(of: mac))
            }
        case .storeIdentity(let mac, let legacyID):
            storeIdentity(mac, legacyID: legacyID, &context)
        case .commitFolder(let folder):
            context.enabled = true
            context.folderID = folder
            context.pendingFolderID = nil
        case .forgetFolder:
            context.enabled = false
            context.folderID = nil
            context.pendingFolderID = nil
        }
    }

    private mutating func readFolder(_ request: SyncReadRequest, _ context: inout SimMacContext) {
        var isJoin = false
        if case .join = request.purpose {
            isJoin = true
        }
        // A join reads the folder the user chose, which is not the sync folder before it commits.
        let saved = context.folderID
        if isJoin, let folder = live?.pendingJoin?.folderIdentity {
            context.folderID = folder
        }
        let result = SimFolderIO.read(request, &context)
        context.folderID = saved
        if isJoin {
            recordJoinRead(result)
        } else {
            for version in newVersions(in: result) {
                context.reportMerge(version: version)
            }
        }
        run(.folderRead(result.read, purpose: request.purpose), &context)
    }

    /// What the join found: the versions it will have seen at the commit, and which listed files it
    /// could not read yet or refused for good.
    private mutating func recordJoinRead(_ result: SimFolderReadResult) {
        lastJoinVersions = result.versions.values.sorted()
        unreadListed = []
        refusedListed = []
        for file in result.read.files {
            guard let mac = file.macID else {
                continue
            }
            let path = SimFolderIO.path(of: mac)
            switch file.state {
            case .dataless, .pending:
                unreadListed.insert(path)
            case .refused(let refusal):
                if refusal == .unreadable {
                    unreadListed.insert(path)
                } else {
                    refusedListed.insert(path)
                }
            case .contents, .conflictCopy:
                break
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

    /// What the host does for `storeIdentity`: the ID, the salt, the hash that binds the ID to this Mac and
    /// this account, and the earlier ID.
    private mutating func storeIdentity(_ mac: SyncMacID, legacyID: String?, _ context: inout SimMacContext) {
        var salt = Data(context.environment.salt.utf8)
        if case .data(let stored)? = context.defaults[Self.deviceSaltKey] {
            salt = stored
        }
        context.defaults[Self.deviceSaltKey] = .data(salt)
        context.defaults[Self.deviceIDKey] = .string(mac.rawValue)
        context.defaults[Self.deviceHashKey] = .string(
            SettingsSyncDevice.hardwareHash(of: context.environment.hardwareID, uid: UInt32(max(0, context.environment.uid)), salt: salt)
        )
        if let legacyID {
            context.defaults[Self.legacyDeviceIDKey] = .string(legacyID)
        }
        if reidentifyReason == nil, cachedReport.deviceID != nil {
            reidentifyReason = inLaunch ? "hardware" : "collision"
        }
    }

    // MARK: Inputs

    private func launchInput(_ context: SimMacContext) -> SyncLaunchInput {
        var generation: UInt64?
        if case .int(let number)? = context.defaults[Self.generationKey] {
            generation = UInt64(max(0, number))
        }
        var lastSynced: Date?
        if case .int(let milliseconds)? = context.defaults[Self.lastSyncedKey] {
            lastSynced = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        var storedID: String?
        if case .string(let id)? = context.defaults[Self.deviceIDKey] {
            storedID = id
        }
        var storedHash: String?
        if case .string(let hash)? = context.defaults[Self.deviceHashKey] {
            storedHash = hash
        }
        var salt: Data?
        if case .data(let data)? = context.defaults[Self.deviceSaltKey] {
            salt = data
        }
        return SyncLaunchInput(
            snapshot: snapshot(context),
            stored: context.sigma.map { SyncStateCodec.decode($0) } ?? .unreadable,
            identity: SyncIdentityInput(
                storedID: storedID,
                storedHash: storedHash,
                salt: salt,
                hardwareID: context.environment.hardwareID,
                uid: UInt32(max(0, context.environment.uid))
            ),
            defaultsGeneration: generation,
            lastSyncedSeen: lastSynced,
            syncIsOn: context.enabled && context.folderID != nil,
            folder: context.folderID
        )
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

    private func store(_ state: SyncState, _ context: inout SimMacContext) {
        context.sigma = try? SyncStateCodec.encode(state)
    }

    private func snapshot(_ context: SimMacContext) -> SyncSnapshot {
        var values: [SyncUnitKey: SyncValue] = [:]
        let isGeneration27 = context.environment.generation == 27
        for (unit, value) in SimUnits.units(of: context.defaults) {
            guard let key = SimEngineUnits.key(ofUnit: unit), table.descriptor(for: key) != nil else {
                continue
            }
            // The macOS 27 families exist only on a generation-27 Mac, as in the app's projection.
            if SyncLayout27.isIntentCaptured(key), !isGeneration27 {
                continue
            }
            values[key] = SyncValue(sim: value) ?? SyncProjection.unrepresentable
        }
        var known: [String] = []
        if isGeneration27, case .array(let elements)? = context.defaults["KnownApplications27"] {
            known = Set(elements.compactMap { element -> String? in
                if case .string(let text) = element { text } else { nil }
            }).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        }
        return SyncSnapshot(values: values, known27: known)
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

    private static let allTimers: [SyncTimer] = [.capture, .relay, .check, .periodic, .healing, .learned]

    static func tag(of timer: SyncTimer) -> String {
        switch timer {
        case .capture: "capture"
        case .relay: "relay"
        case .check: "check"
        case .periodic: "periodic"
        case .healing: "healing"
        case .learned: "learned"
        }
    }

    private static func timer(forTag tag: String) -> SyncTimer? {
        allTimers.first { self.tag(of: $0) == tag }
    }

    // MARK: The sheet

    /// Opens the sheet when the engine has a question and the hint shows; closes it when the question
    /// is gone (answered, or decided elsewhere) or the hint hides (Later). A sheet that is open stays as
    /// it was shown, and a new one never opens in the hook that closed the last, as in the app.
    private mutating func updatePrompt(_ context: inout SimMacContext) {
        guard let state = live else {
            question = nil
            prompt = nil
            return
        }
        let current = SyncEngine.question(for: state, scope: .mine, environment: environment(context))
        let isShowing = cachedView.hint == .choose || cachedView.hint == .chooseAfterJoin
        if prompt != nil {
            // Closed: answered, decided elsewhere (none of its rows is a question any more) or hidden by Later.
            let rows = Set(question?.rows.map(\.unit) ?? [])
            if current == nil || !isShowing || rows.isDisjoint(with: current?.rows.map(\.unit) ?? []) {
                question = nil
                prompt = nil
            }
            return
        }
        guard let current, isShowing, !promptWasOpenAtStart else {
            return
        }
        promptCounter += 1
        let opened = Self.simPrompt(for: current, id: promptCounter)
        question = current
        prompt = opened
        context.reportPrompt(opened)
    }

    private static func simPrompt(for question: SyncQuestion, id: Int) -> SimPrompt {
        var shown: [SimPromptUnit] = []
        for row in question.rows {
            let unit = SimEngineUnits.unit(of: row.unit)
            let local = row.local.flatMap(token(of:))
            if row.style == .multi || row.style == .bystander, !row.folder.isEmpty {
                // A pop-up row: Use takes one value and Keep another, and every other value shown loses either way.
                // Each token is listed once, on the side that loses it, so the oracles' model of what an answer
                // takes away is what the engine's answer supersedes.
                let chosenToUse = row.folder[index(of: .use, in: row)].value
                let chosenToKeep = row.folder[index(of: .keep, in: row)].value
                var tokens: [String] = []
                for token in ([row.local].compactMap { $0 } + row.folder).compactMap(token(of:)) where !tokens.contains(token) {
                    tokens.append(token)
                }
                let used = token(ofPayload: chosenToUse)
                let kept = token(ofPayload: chosenToKeep)
                for token in tokens where token != used || token != kept {
                    shown.append(SimPromptUnit(unit: unit, local: token == used ? nil : token, folder: token == kept ? nil : token))
                }
                continue
            }
            for value in row.folder {
                shown.append(SimPromptUnit(unit: unit, local: local, folder: token(of: value)))
            }
            if case .clash(let partner) = row.style {
                // The other hotkey that holds the combination is what the answer may take away.
                shown.append(SimPromptUnit(unit: SimEngineUnits.unit(of: partner), local: nil, folder: row.folder.first.flatMap(token(of:))))
            }
        }
        let title = question.kind == .joining ? "This folder already holds holzBar settings" : "Which settings should holzBar use?"
        return SimPrompt(id: id, title: title, shown: shown)
    }

    private static func token(of value: SyncRowValue) -> String? {
        token(ofPayload: value.value)
    }

    private static func token(ofPayload payload: SyncPayload) -> String? {
        guard case .value(let synced) = payload, let value = SimValue(sync: synced) else {
            return nil
        }
        return value.tokens.first
    }

    /// The simulator's answer as the engine's: the button, and for every pop-up row the pick that goes
    /// with the button (Use takes a value of the folder, Keep the value this Mac holds).
    private mutating func answer(_ answer: SimAnswer, _ context: inout SimMacContext) {
        guard let question, prompt != nil else {
            return
        }
        var choices: [SyncUnitKey: Int] = [:]
        let button: SyncAnswerButton
        switch answer {
        case .use:
            button = .use
        case .keep:
            button = .keep
        case .later:
            button = .later
        case .cancel:
            button = .cancel
        case .pick(let picks):
            button = .useChosen
            for (unit, side) in picks {
                guard let key = SimEngineUnits.key(ofUnit: unit), let row = question.rows.first(where: { $0.unit == key }) else {
                    continue
                }
                choices[key] = Self.index(of: side == .local ? .keep : .use, in: row)
            }
        }
        for row in question.rows where choices[row.unit] == nil {
            switch row.style {
            case .multi, .bystander:
                choices[row.unit] = Self.index(of: answer == .keep ? .keep : .use, in: row)
            default:
                break
            }
        }
        let before = live
        run(.command(.answer(SyncAnswerRequest(button: button, choices: choices, question: question))), &context)
        // An answer the engine took changes its state (entries written, the join committed or cancelled,
        // Later recorded); the sheet is done then, whatever the engine asks next.
        if let before, let after = live, before.replica != after.replica || before.pendingJoin != after.pendingJoin
            || before.laterLaunch != after.laterLaunch || before.isEnabled != after.isEnabled {
            self.question = nil
            prompt = nil
        }
    }

    /// The index of the value a pop-up pick takes: the value this Mac holds for Keep, another one for Use.
    private static func index(of answer: SimAnswer, in row: SyncRow) -> Int {
        let local = row.local?.value
        if answer == .keep {
            return row.folder.firstIndex { $0.value == local } ?? 0
        }
        return row.folder.firstIndex { $0.value != local } ?? 0
    }

    // MARK: Bookkeeping for the oracles

    /// Remembers the token every live entry carries, by dot.
    private mutating func learn(_ state: SyncState) {
        for replica in [state.replica, state.pendingJoin?.replica].compactMap({ $0 }) {
            for key in replica.keys {
                for entry in replica.live(key) {
                    dotTokens[entry.dot, default: []].formUnion(Self.tokens(of: entry))
                }
            }
        }
    }

    private static func tokens(of entry: SyncEntry) -> Set<String> {
        guard let value = entry.value, let sim = SimValue(sync: value) else {
            return []
        }
        return Set(sim.tokens)
    }

    private mutating func refresh(_ context: inout SimMacContext) {
        guard let state = live else {
            return
        }
        let environment = environment(context)
        cachedView = SyncEngine.view(of: state, environment: environment)
        context.pendingFolderID = state.pendingJoin?.folderIdentity
        updatePrompt(&context)
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
        // What a join has read but not committed is held too: nothing is lost while the question waits.
        if let pending = state.pendingJoin {
            for key in pending.replica.keys {
                for entry in pending.replica.live(key) {
                    held.formUnion(Self.tokens(of: entry))
                }
            }
        }
        cachedHeld = held
        var report = SimBrainReport()
        report.deviceID = state.mac.rawValue
        report.ownFilePath = SimFolderIO.path(of: state.mac)
        report.joining = state.pendingJoin != nil || joinedInHook
        report.joinCommitted = state.pendingJoin == nil && context.enabled
        report.unreadListedFiles = unreadListed
        report.refusedFiles = refusedListed
        report.reidentifyReason = reidentifyReason
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
        // The oracle asks for user changes: a value that was there before sync and a value holzBar
        // placed itself are held and relayed, but they are no user change that a file could claim.
        var claimed = Set<String>()
        for (dot, tokens) in dotTokens where contents.replica.context.covers(dot) {
            for token in tokens {
                if case .user? = SimValue.origin(ofToken: token) {
                    claimed.insert(token)
                }
            }
        }
        return claimed
    }

    func deletedUnits(inFile path: String, data: Data) -> Set<String>? {
        guard let contents = Self.contents(path: path, data: data) else {
            return nil
        }
        var units = Set<String>()
        for key in contents.replica.keys where contents.replica.live(key).contains(where: { Self.isDeletion($0.payload, of: key) }) {
            units.insert(SimEngineUnits.unit(of: key))
        }
        return units
    }

    /// A deletion, or for the arrangement the explicit visible section: in the defaults visible is no entry.
    private static func isDeletion(_ payload: SyncPayload, of key: SyncUnitKey) -> Bool {
        if payload == .deleted {
            return true
        }
        if case .split(SyncUnitTable.layout27Family, _) = key, payload == .value(SyncLayout27.visible) {
            return true
        }
        return false
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
