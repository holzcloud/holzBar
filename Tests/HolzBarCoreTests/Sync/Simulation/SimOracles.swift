import Foundation

// MARK: - Violations, moments and the oracle protocol

/// The ID of an invariant, such as `INV-S1` (analysis section 2.2).
struct SimInvariantID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static func < (lhs: SimInvariantID, rhs: SimInvariantID) -> Bool { lhs.rawValue < rhs.rawValue }
    var description: String { rawValue }
}

/// When an oracle runs: after every step, every write, every read, every prompt and every answer, after a
/// drain phase, or as a metamorphic pair of runs (analysis section 2.2).
enum SimCheckMoment: Hashable, Sendable {
    case step, write, read, prompt, answer, drain, meta
}

/// A failed invariant, with what is needed to reproduce and print it.
struct SimViolation: Equatable, Sendable {
    var id: SimInvariantID
    var seed: UInt64
    var stepIndex: Int
    var description: String
    /// The canonical events of the run up to the violation.
    var trace: [String]
}

/// One invariant checked against the ground truth, never against engine metadata.
protocol SimOracle: Sendable {
    var id: SimInvariantID { get }
    var moment: SimCheckMoment { get }
    /// Called at its moment; the thing just observed is `world.focus`. `event` is the step's event, if any.
    func check(_ world: SimWorld, event: SimEvent?) -> SimViolation?
}

/// An oracle written as a closure that returns the violation text. Most invariants are one.
struct SimClosureOracle: SimOracle {
    let id: SimInvariantID
    let moment: SimCheckMoment
    let body: @Sendable (SimWorld, SimEvent?) -> String?

    init(
        _ id: SimInvariantID,
        _ moment: SimCheckMoment,
        _ body: @escaping @Sendable (SimWorld, SimEvent?) -> String?
    ) {
        self.id = id
        self.moment = moment
        self.body = body
    }

    func check(_ world: SimWorld, event: SimEvent?) -> SimViolation? {
        body(world, event).map { world.violation(id, $0) }
    }
}

/// The oracles a run uses. Later plans register their families with `adding` (the macOS 27 and profile oracles
/// of plan 28-09 do: `SimOracleSet.safety.adding(SimLayout27Oracles.all)`).
struct SimOracleSet: Sendable {
    var oracles: [any SimOracle]

    init(_ oracles: [any SimOracle] = []) { self.oracles = oracles }

    static let none = SimOracleSet()
    /// Every safety invariant the world can observe.
    static let safety = SimOracleSet(SimSafetyOracles.all).adding(layout27)
    /// The invariants of the macOS 27 families: INV-L1 to INV-L6, INV-K1 and the automatic-store rule. They
    /// stay quiet in a world without a generation-27 Mac, so the safety set includes them for every world.
    static let layout27 = SimOracleSet(SimLayout27Oracles.all)
    /// The liveness checks of the drain phase.
    static let liveness = SimOracleSet(SimLivenessOracles.all)

    func adding(_ more: [any SimOracle]) -> SimOracleSet {
        var ids = Set(oracles.map(\.id))
        var merged = oracles
        for oracle in more where ids.insert(oracle.id).inserted { merged.append(oracle) }
        return SimOracleSet(merged)
    }

    func adding(_ other: SimOracleSet) -> SimOracleSet { adding(other.oracles) }

    func only(_ ids: [SimInvariantID]) -> SimOracleSet {
        SimOracleSet(oracles.filter { ids.contains($0.id) })
    }

    func without(_ ids: [SimInvariantID]) -> SimOracleSet {
        SimOracleSet(oracles.filter { !ids.contains($0.id) })
    }

    func oracles(at moment: SimCheckMoment) -> [any SimOracle] {
        oracles.filter { $0.moment == moment }
    }

    var ids: [SimInvariantID] { oracles.map(\.id).sorted() }
}

// MARK: - Engine introspection (optional)

/// What a redesigned engine says about itself so the oracles can check what the world cannot see from outside.
/// A brain that does not conform (the control engines, the beta1 and beta2 peers) is simply not checked by the
/// oracles that need it: violations are charged to redesigned Macs only (INV-B1).
struct SimBrainReport: Equatable, Sendable {
    /// The ID the Mac publishes under, and its file `holzBar/Macs/<id>.plist`.
    var deviceID: String?
    var ownFilePath: String?
    var joining = false
    var joinCommitted = false
    /// Device files the join listed but has not read, and the ones refused for a lasting reason.
    var unreadListedFiles: Set<String> = []
    var refusedFiles: Set<String> = []
    /// Why the ID changed at the last launch: `hardware`, `collision`, `reset`.
    var reidentifyReason: String?
    /// Paths treated as foreign because they carry this Mac's ID without being written by it (INV-ID3).
    var foreignPaths: Set<String> = []
    /// The Mac's own highest counter, for the dot-reuse check (INV-ID6).
    var ownCounter: Int?
    /// Units of deletions the Mac published because of a re-key (INV-A6).
    var rekeyDeletions: Set<String> = []
    var menuHint = false
    /// A warning that the state is too large to publish (INV-Z3).
    var sizeWarning = false
    var sigmaBytes = 0
    var devicesSeen = 0
    var mountAttempts = 0
    var usedLegacyStateAsEvidence = false
    /// The user-change tokens this Mac's applied context covers.
    var appliedTokens: Set<String> = []
    /// Tokens the Mac holds as waiting changes (answer pending, Restart pending).
    var waitingTokens: Set<String> = []

    init() {}
}

protocol SimBrainIntrospection: SimSyncBrain {
    func report() -> SimBrainReport
    /// The units a file explicitly deletes; `nil` when the format has no deletion entries.
    func deletedUnits(inFile path: String, data: Data) -> Set<String>?
    /// The units a file mentions at all.
    func mentionedUnits(inFile path: String, data: Data) -> Set<String>?
    /// The device ID a file says it was written by.
    func writerID(inFile path: String, data: Data) -> String?
    /// The highest counter of `device` the file's context claims.
    func claimedCounter(ofDevice device: String, inFile path: String, data: Data) -> Int?
}

extension SimBrainIntrospection {
    func deletedUnits(inFile path: String, data: Data) -> Set<String>? { nil }
    func mentionedUnits(inFile path: String, data: Data) -> Set<String>? { nil }
    func writerID(inFile path: String, data: Data) -> String? { nil }
    func claimedCounter(ofDevice device: String, inFile path: String, data: Data) -> Int? { nil }
}

// MARK: - Observations

enum SimHookName: String, Sendable {
    case launch, quit, defaultsChanged, folderSignal, timer, command, answer
}

/// A change of one unit's value that a hook made.
struct SimTransition: Equatable, Sendable {
    var mac: SimMacName
    var unit: String
    var old: SimValue?
    var new: SimValue?

    var oldTokens: Set<String> { Set(old?.tokens ?? []) }
    var newTokens: Set<String> { Set(new?.tokens ?? []) }
}

/// A change of one top-level defaults key, including local keys.
struct SimKeyChange: Equatable, Sendable {
    var mac: SimMacName
    var key: String
    var old: SimValue?
    var new: SimValue?
}

struct SimAnsweredPrompt: Equatable, Sendable {
    var prompt: SimPrompt
    var answer: SimAnswer
}

/// One write handed to the provider, with what the writer's replica held before it.
struct SimWriteRecord: Sendable {
    var mac: SimMacName
    var folder: String
    var path: String
    var data: Data
    /// The provider version; `nil` when the write failed (unmounted folder).
    var version: Int?
    var time: Int64
    var stepIndex: Int
    var brainKind: SimMacVersion
    var changeCount: Int
    var previousEntry: SimFolderEntry
    var previousVersion: Int
    /// Whether the previous version's past is within the writer's own past (ground truth).
    var previousDominated: Bool
    /// The writer read or wrote the previous version in its current session.
    var previousSeenInSession: Bool
    /// The provider version the previous content has: a foreign one has no writer.
    var previousKind: SimVersion.Kind?
    var previousWriter: SimMacName?
    var hook: SimHookName
    var ingestsSoFar: [Int]
    var unmounted: Bool
}

struct SimReadRecord: Sendable {
    var mac: SimMacName
    var entry: SimReadLogEntry
    /// The provider version of the bytes that came back (0 when nothing did).
    var version: Int
    /// The provider version the Mac's replica holds at the path, whatever the read returned.
    var replicaVersion: Int = 0
    var versionKind: SimVersion.Kind?
    var versionWriter: SimMacName?
    var stepIndex: Int
    var hook: SimHookName
}

struct SimPromptRecord: Sendable {
    var mac: SimMacName
    var prompt: SimPrompt
    var stepIndex: Int
    var time: Int64
    var hook: SimHookName
    /// Another sheet this Mac had open when this one appeared.
    var openBefore: SimPrompt?
}

struct SimAnswerRecord: Sendable {
    var mac: SimMacName
    var prompt: SimPrompt
    var answer: SimAnswer
    var stepIndex: Int
    var time: Int64
    var transitions: [SimTransition]
    var writes: [SimWriteRecord]
}

/// Everything one hook did that an oracle may want.
struct SimHookRecord: Sendable {
    var mac: SimMacName
    var name: SimHookName
    var stepIndex: Int
    var brainKind: SimMacVersion
    /// The Mac's brain made these changes (sync-caused, unlike a beta2 Mac's load-time writers).
    var syncCaused: Bool
    var changeCountBefore: Int
    var blockedMilliseconds: Int64
    var ingests: [Int] = []
    /// The ingests whose past was already inside the Mac's own past (a dominated version changes nothing).
    var dominatedIngests: [Int] = []
    var transitions: [SimTransition] = []
    var keyChanges: [SimKeyChange] = []
    var reads: [SimReadRecord] = []
    var writes: [SimWriteRecord] = []
    var prompts: [SimPrompt] = []
    var answered: SimAnsweredPrompt?
    /// The sheet that was open when the hook began, if any.
    var openPromptAtStart: SimPrompt?
}

/// A Mac as the oracles see it before and after a step.
struct SimMacSnapshot: Equatable, Sendable {
    var version: SimMacVersion
    var generation: Int
    var running: Bool
    var enabled: Bool
    var folderID: String?
    var hint: String?
    var openPrompt: SimPrompt?
    var heldTokens: Set<String>
    var defaultsTokens: Set<String>
    var report: SimBrainReport?
}

struct SimStepRecord: Sendable {
    var index: Int
    var event: SimEvent
    var time: Int64
    var before: [SimMacName: SimMacSnapshot]
    var after: [SimMacName: SimMacSnapshot] = [:]
    var hooks: [SimHookRecord] = []
    var prompts: [SimPromptRecord] = []
    var answers: [SimAnswerRecord] = []
    var writeViolationsAdded = 0

    var writes: [SimWriteRecord] { hooks.flatMap(\.writes) }
    var transitions: [SimTransition] { hooks.flatMap(\.transitions) }
}

/// The thing that was just observed, for the oracle that runs at its moment.
enum SimFocus: Sendable {
    case step(SimStepRecord)
    case write(SimWriteRecord)
    case read(SimReadRecord)
    case prompt(SimPromptRecord)
    case answer(SimAnswerRecord)
}

// MARK: - Limits and local keys

/// The size limits the oracles check (analysis section 4.9; INV-Z1, Z2).
enum SimLimits {
    /// The most bytes a device file may have, and the most bytes a reader accepts.
    static let deviceFileWriter = 1 << 20
    static let deviceFileReader = 1 << 20
    /// The state size above which a Mac must show the "too large" warning.
    static let stateSizeWarning = 1 << 20
    /// The device file name pattern.
    static let devicePrefix = "holzBar/Macs/"
    static let legacyPath = SimMacBeta1.filePath

    static func isDeviceFile(_ path: String) -> Bool {
        path.hasPrefix(devicePrefix) && path.hasSuffix(".plist")
    }
}

/// The keys no sync-caused change may touch (INV-N1, decisions D-04 to D-06).
enum SimLocalKeys {
    /// Local in every generation: the arrangement of macOS 26, the learned sets, the one-time flags, the
    /// current layout profile, the device tuning keys and everything of sync itself.
    static let always: Set<String> = [
        "ItemSections", "KnownItemTags", "TitleChangingItemOwners", "CurrentLayoutProfile",
        "MacOS27LayoutSeeded", "HasImportedIceSettings",
    ]
    /// Device tuning keys. The simulator's key model has none yet; the plans that add one list it here.
    static let tuning: Set<String> = []
    /// The keys sync keeps its own bookkeeping in: the generation and the counter mirror, and the Mac's
    /// identity (the ID, the hash that binds it to this Mac and account, the salt and the earlier ID).
    /// The engine writes them on purpose before it persists its state (analysis sections 4.4 and 4.5),
    /// so INV-N1 leaves them out. `SettingsSyncLastSynced` is not among them: sync never writes it.
    static let syncBookkeeping: Set<String> = [
        "SettingsSyncGeneration", "SettingsSyncCounter", "SettingsSyncDeviceID", "SettingsSyncDeviceHash",
        "SettingsSyncDeviceSalt", "SettingsSyncLegacyDeviceID",
    ]
    /// Local on generation 26 Macs: the macOS 27 families are only applied on generation 27.
    static let generation27Only: Set<String> = ["MacOS27Layout", "LayoutProfiles", "KnownApplications27"]

    static func isLocal(_ key: String, generation: Int) -> Bool {
        if always.contains(key) || tuning.contains(key) || SimKeys.isLocal(key) || key.hasPrefix("Has") { return true }
        if generation != 27, generation27Only.contains(key) { return true }
        return false
    }

    /// Whether a unit is synced between two Macs of these generations (used by the drain and the agreement check).
    static func isSyncedUnit(_ unit: String, generation: Int) -> Bool {
        let key = SimUnits.parse(unit).key
        if SimKeys.entryGranular[key] == "ItemSections" || key == "ItemSections" { return false }
        return !isLocal(key, generation: generation)
    }
}

// MARK: - World helpers for oracles

extension SimWorld {
    /// A violation of `id`, stamped with the seed, step and trace of this run.
    func violation(_ id: SimInvariantID, _ description: String) -> SimViolation {
        SimViolation(id: id, seed: seed, stepIndex: stepIndex, description: description, trace: groundTruth.eventLog)
    }

    /// Redesigned Macs are charged with violations; beta1 and beta2 peers are not (INV-B1).
    func isRedesign(_ mac: SimMacName) -> Bool {
        guard let version = macs[mac]?.version else { return false }
        return version == .redesign || version == .redesignSkew
    }

    func introspection(of mac: SimMacName) -> (any SimBrainIntrospection)? {
        brains[mac] as? any SimBrainIntrospection
    }

    func kind(ofVersion id: Int) -> SimVersion.Kind? {
        for folder in providers.keys.sorted() {
            if let version = providers[folder]!.version(id) { return version.kind }
        }
        return nil
    }

    func writer(ofVersion id: Int) -> SimMacName? {
        for folder in providers.keys.sorted() {
            if let version = providers[folder]!.version(id) { return version.writer }
        }
        return nil
    }

    func path(ofVersion id: Int) -> String? {
        for folder in providers.keys.sorted() {
            if let version = providers[folder]!.version(id) { return version.path }
        }
        return nil
    }

    func data(ofVersion id: Int) -> Data? {
        for folder in providers.keys.sorted() {
            if let version = providers[folder]!.version(id) { return version.data }
        }
        return nil
    }

    /// All user-change tokens in the past of a Mac, by ground truth.
    func userTokens(inPastOf mac: SimMacName) -> Set<String> {
        var tokens = Set<String>()
        let past = groundTruth.seenPast(ofMac: mac)
        for change in groundTruth.changes where past.contains(change.id) { tokens.formUnion(change.tokens) }
        return tokens
    }

    func userTokens(inPastOfVersion version: Int) -> Set<String> {
        var tokens = Set<String>()
        let past = groundTruth.past(ofVersion: version)
        for change in groundTruth.changes where past.contains(change.id) { tokens.formUnion(change.tokens) }
        return tokens
    }

    /// The tokens of a user-minted unit value, by unit.
    static func unit(ofToken token: String) -> String? {
        if case .user(_, let unit)? = SimValue.origin(ofToken: token) { return unit }
        return nil
    }
}

/// A small memo the oracles of one world share.
final class SimOracleCache {
    private var lists: [String: [String]] = [:]

    func list(_ key: String, _ build: () -> [String]) -> [String] {
        if let known = lists[key] { return known }
        let built = build()
        lists[key] = built
        return built
    }
}
