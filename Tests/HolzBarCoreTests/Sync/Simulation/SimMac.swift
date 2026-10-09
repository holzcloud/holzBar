import Foundation

// MARK: - Mac kinds and state

/// Which app build a simulated Mac runs.
enum SimMacVersion: String, Hashable, Sendable, CaseIterable {
    /// 0.0.6 and 0.0.7-beta1: the shared-file sync peer (A2 section 2.6). Called L1 in A2.
    case beta1
    /// 0.0.7-beta2: inert towards the folder, but its load-time writers run at every launch (P in A2).
    case beta2
    /// The redesigned engine (N).
    case redesign
    /// A second redesigned build with another unit table (N-skew).
    case redesignSkew
}

/// The identity markers each Mac carries so the privacy oracle can scan every written byte for them (INV-PR2).
struct SimIdentityMarkers: Equatable, Sendable {
    var hardwareID: String
    var computerName: String
    var userName: String
    var homePath: String
    var salt: String

    init(mac: SimMacName) {
        hardwareID = "MARKER-HW-\(mac.name)"
        computerName = "MARKER-NAME-\(mac.name)"
        userName = "MARKER-USER-\(mac.name)"
        homePath = "/Users/MARKER-USER-\(mac.name)"
        salt = "MARKER-SALT-\(mac.name)"
    }

    /// Every marker string, in a fixed order.
    var all: [String] { [hardwareID, computerName, userName, homePath, salt] }
}

/// What a brain may know about the Mac it runs on.
struct SimEnvironment: Equatable, Sendable {
    var generation: Int
    var hardwareID: String
    var uid: Int
    var computerName: String
    var userName: String
    var homePath: String
    var salt: String
    var version: SimMacVersion
}

/// One Mac's persistent state, which survives quit and crash.
struct SimMacState: Sendable {
    var name: SimMacName
    var version: SimMacVersion
    var markers: SimIdentityMarkers
    var uid: Int
    /// 26 for every macOS before 27, 27 for macOS 27.
    var generation: Int
    var running = false
    /// Whether sync is turned on, and the folder it points to (the simulator's stand-in for the bookmark).
    var enabled = false
    var folderID: String?
    /// The folder a join reads before it commits: the user chose it, but it is not yet the sync folder.
    var pendingFolderID: String?
    var defaults: [String: SimValue] = [:]
    /// The opaque local sync state (Sigma). Never synced.
    var sigma: Data?
    /// The opaque high-water cache outside the preferences.
    var caches: Data?
    var random: SimRandom

    var environment: SimEnvironment {
        SimEnvironment(
            generation: generation,
            hardwareID: markers.hardwareID,
            uid: uid,
            computerName: markers.computerName,
            userName: markers.userName,
            homePath: markers.homePath,
            salt: markers.salt,
            version: version
        )
    }
}

// MARK: - Defaults keys and units

/// The simulator's model of the defaults keys, their kinds and which of them the old peer treats as local.
enum SimKeys {
    /// Importable keys and the value kind the old peer's schema accepts for each.
    static let importable: [String: SimValue.Kind] = [
        "ShowOnHover": .scalar, "UseIceBar": .scalar, "HideApplicationMenus": .scalar,
        "ShowSectionDividers": .scalar, "ItemSpacingOffset": .scalar, "RehideInterval": .scalar,
        "ItemSections": .dictionary, "Hotkeys": .dictionary, "ItemIcons": .dictionary,
        "RevealRules": .dictionary, "MacOS27Layout": .dictionary, "LayoutProfiles": .dictionary,
        "IceIcon": .data, "MenuBarAppearanceConfigurationV2": .data, "ItemGroups": .data,
        "KnownApplications27": .array, "KnownItemTags": .array, "TitleChangingItemOwners": .array,
    ]

    /// The keys that are never importable (A2 section 2.6: local keys and flags).
    static let localKeys: Set<String> = [
        "SyncsSettingsWithICloud", "SettingsSyncLastSynced", "SettingsSyncDeviceID", "HasImportedIceSettings",
    ]
    static let localPrefixes = ["SettingsSync", "NSWindow Frame", "NSStatusItem", "SU"]

    static func isLocal(_ key: String) -> Bool {
        localKeys.contains(key) || localPrefixes.contains { key.hasPrefix($0) }
    }

    /// Importable keys in a fixed order.
    static var importableKeys: [String] { importable.keys.sorted() }

    /// Keys whose entries are separate atoms (A2 section 2.3), with the unit prefix of each.
    static let entryGranular: [String: String] = [
        "ItemSections": "ItemSections", "Hotkeys": "Hotkeys", "ItemIcons": "ItemIcons",
        "RevealRules": "RevealRules", "MacOS27Layout": "l27", "LayoutProfiles": "prof",
    ]

    /// The macOS 27 apps the simulator knows.
    static let apps27 = ["com.app.a", "com.app.b", "com.app.c", "com.app.d"]

    /// The clamp ranges the 0.0.7-beta2 load-time writers apply.
    static let itemSpacingRange = -16...16
    static let rehideIntervalRange = 1...300
}

/// Units are the atoms of comparison and of user change: a scalar key, or one entry of an entry-granular key.
enum SimUnits {
    static let known27 = "known27"

    static func unitName(key: String, entry: String?) -> String {
        if key == "KnownApplications27" { return known27 }
        guard let entry, let prefix = SimKeys.entryGranular[key] else { return key }
        return "\(prefix)/\(entry)"
    }

    /// Splits a unit into the defaults key and the entry (nil for a whole-key unit).
    static func parse(_ unit: String) -> (key: String, entry: String?) {
        if unit == known27 { return ("KnownApplications27", nil) }
        guard let slash = unit.firstIndex(of: "/") else { return (unit, nil) }
        let prefix = String(unit[..<slash])
        let entry = String(unit[unit.index(after: slash)...])
        for (key, keyPrefix) in SimKeys.entryGranular.sorted(by: { $0.key < $1.key }) where keyPrefix == prefix {
            return (key, entry)
        }
        return (unit, nil)
    }

    /// The generation a unit exists for: 27 for `l27/*`, `prof/*` and `known27`, otherwise `nil` (both).
    static func generationScope(_ unit: String) -> Int? {
        unit.hasPrefix("l27/") || unit.hasPrefix("prof/") || unit == known27 ? 27 : nil
    }

    /// The unit's value in a defaults dictionary.
    static func value(of unit: String, in defaults: [String: SimValue]) -> SimValue? {
        let (key, entry) = parse(unit)
        guard let entry else { return defaults[key] }
        if case .dictionary(let entries)? = defaults[key] { return entries[entry] }
        return nil
    }

    /// Sets or (with `nil`) removes the unit's value.
    static func set(_ unit: String, to value: SimValue?, in defaults: inout [String: SimValue]) {
        let (key, entry) = parse(unit)
        guard let entry else {
            defaults[key] = value
            if value == nil { defaults[key] = nil }
            return
        }
        var entries: [String: SimValue] = [:]
        if case .dictionary(let existing)? = defaults[key] { entries = existing }
        entries[entry] = value
        defaults[key] = entries.isEmpty && value == nil ? nil : .dictionary(entries)
    }

    /// All non-local units of a defaults dictionary with their values, sorted by unit name.
    static func units(of defaults: [String: SimValue]) -> [(unit: String, value: SimValue)] {
        var result: [(unit: String, value: SimValue)] = []
        for key in defaults.keys.sorted() where !SimKeys.isLocal(key) {
            guard let value = defaults[key] else { continue }
            if SimKeys.entryGranular[key] != nil, case .dictionary(let entries) = value {
                for entry in entries.keys.sorted() {
                    result.append((unitName(key: key, entry: entry), entries[entry]!))
                }
            } else {
                result.append((unitName(key: key, entry: nil), value))
            }
        }
        return result.sorted { $0.unit < $1.unit }
    }

    /// Whether two values of a unit are the same setting. A JSON setting that the app's models decode and encode again
    /// (the appearance) is one setting whatever the key order and the fields the build fills or drops; every other value
    /// is the same only when it is equal.
    static func equivalent(_ unit: String, _ left: SimValue?, _ right: SimValue?) -> Bool {
        if left == right { return true }
        // The known applications and the learned items are sets that grow by union: their order says nothing.
        if case .array(let first)? = left, case .array(let second)? = right, unit == known27 {
            return Set(first.map(\.canonical)) == Set(second.map(\.canonical))
        }
        guard case .data(let first)? = left, case .data(let second)? = right else { return false }
        let key = parse(unit).key
        guard let one = SimMacBeta2.reencoded(first, key: key), let other = SimMacBeta2.reencoded(second, key: key) else { return false }
        return one == other
    }

    /// Every token held in the defaults, by unit (sorted).
    static func tokens(in defaults: [String: SimValue]) -> Set<String> {
        var found = Set<String>()
        for (_, value) in units(of: defaults) { found.formUnion(value.tokens) }
        return found
    }
}

// MARK: - Brain protocol and context

/// Who changed the defaults.
enum SimChangeOrigin: Hashable, Sendable {
    case user
    case automatic
}

/// The sync-related commands a user gives the app.
enum SimUserCommand: Hashable, Sendable {
    case turnOn(folder: String)
    case turnOff
    case changeFolder(folder: String)
    case restart
    /// An import of a settings file, already applied to the defaults by the world (with remove-missing).
    case importFile(set: [String], removed: [String])
    case answer(SimAnswer)
}

/// One unit of an open prompt: what each side holds.
struct SimPromptUnit: Hashable, Sendable {
    var unit: String
    /// The token this Mac holds at the unit (nil: nothing).
    var local: String?
    /// The token the folder version holds.
    var folder: String?
    /// A value of a pop-up row that loses whichever button is pressed: it is listed on both sides so that either answer takes
    /// it away, which is no sign that the two sides are equal. It is no part of what two entries compare as.
    var losesEitherWay = false

    init(unit: String, local: String?, folder: String?, losesEitherWay: Bool = false) {
        self.unit = unit
        self.local = local
        self.folder = folder
        self.losesEitherWay = losesEitherWay
    }

    static func == (lhs: SimPromptUnit, rhs: SimPromptUnit) -> Bool {
        lhs.unit == rhs.unit && lhs.local == rhs.local && lhs.folder == rhs.folder
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(unit)
        hasher.combine(local)
        hasher.combine(folder)
    }
}

/// A sheet or alert the app shows. `shown` is what the user is shown; supersession is judged against it.
struct SimPrompt: Hashable, Sendable {
    var id: Int
    var title: String
    var shown: [SimPromptUnit]

    /// The tokens that lose when the user gives this answer (the losing alternative of each shown unit).
    func losingTokens(for answer: SimAnswer) -> Set<String> {
        var lost = Set<String>()
        for entry in shown {
            switch answer {
            case .use:
                if let local = entry.local { lost.insert(local) }
            case .keep:
                if let folder = entry.folder { lost.insert(folder) }
            case .pick(let picks):
                switch picks[entry.unit] {
                case .folder?: if let local = entry.local { lost.insert(local) }
                case .local?: if let folder = entry.folder { lost.insert(folder) }
                case nil: break
                }
            case .later, .cancel:
                break
            }
        }
        return lost
    }
}

/// What a hook did that the world must carry out or record, in order.
enum SimMacAction: Equatable, Sendable {
    case write(folder: String, path: String, data: Data)
    /// The brain decided on a version: it merged, applied, adopted, found it dominated, or answered a prompt about it.
    case ingest(version: Int)
    /// A redesigned Mac merged a version into its replica without applying it or asking its user: it relays it.
    case merged(version: Int)
    case promptShown(SimPrompt)
    case requestDownload(folder: String, path: String)
    case schedule(afterMilliseconds: Int64, tag: String)
    case cancelTimer(tag: String)
    case resolveConflictVersions(folder: String, path: String)
    /// The Mac's own app wrote a defaults unit without the user (a load-time writer).
    case automaticWrite(unit: String)
    case relaunch
    case note(String)
}

/// One read a hook made: what was asked and what came back.
struct SimReadLogEntry: Equatable, Sendable {
    var path: String
    var maximumBytes: Int
    var result: SimReadResult
    /// The replica held truncated or in-progress content at the path when the read began.
    var wasPartial: Bool
}

/// Everything a hook can touch. The world builds it from the Mac's state and the folder replica, hands it in
/// `inout`, and carries out the recorded actions afterwards.
struct SimMacContext: Sendable {
    let mac: SimMacName
    var environment: SimEnvironment
    var defaults: [String: SimValue]
    /// The opaque local sync state (Sigma).
    var sigma: Data?
    /// The opaque high-water cache.
    var caches: Data?
    /// The Mac's own wall clock, offset included. The only time a brain may read.
    var wallClock: Date
    /// The Mac's own random stream.
    var random: SimRandom
    var enabled: Bool
    var folderID: String?
    /// The folder of a pending join. Reads of the join see its replica, not the sync folder's.
    var pendingFolderID: String?

    /// The world asks the Mac to crash after this many effects of the hook (`nil`: no crash).
    var crashAfterEffects: Int?
    /// How many effects the brain has carried out in this hook.
    private(set) var effectsRun = 0
    /// Whether the crash the world asked for has happened: the brain carries out no further effect.
    private(set) var crashed = false

    /// A copy of the Mac's replica at the start of the hook (reads and the Mac's own writes see it).
    private(set) var replica: SimFolderReplica
    /// The global virtual time, used only for stall and partial-exposure semantics. Brains must not read it.
    private let globalNow: Int64
    var ioTimeoutMilliseconds: Int64
    private(set) var actions: [SimMacAction] = []
    /// How long the Mac's calling thread blocked on stalled coordinated I/O during this hook.
    private(set) var blockedMilliseconds: Int64 = 0

    /// A read that the app runs in the background (a check, the read of a join) blocks no thread of the Mac that launches: what it
    /// waited for is not the launch's time.
    mutating func discardBlocking(since earlier: Int64) {
        blockedMilliseconds = earlier
    }
    /// Every bounded read of this hook, for the oracles (INV-F1, INV-Z2).
    private(set) var readLog: [SimReadLogEntry] = []

    init(
        mac: SimMacName,
        state: SimMacState,
        wallClock: Date,
        replica: SimFolderReplica,
        globalNow: Int64,
        ioTimeoutMilliseconds: Int64
    ) {
        self.mac = mac
        environment = state.environment
        defaults = state.defaults
        sigma = state.sigma
        caches = state.caches
        self.wallClock = wallClock
        random = state.random
        enabled = state.enabled
        folderID = state.folderID
        pendingFolderID = state.pendingFolderID
        self.replica = replica
        self.globalNow = globalNow
        self.ioTimeoutMilliseconds = ioTimeoutMilliseconds
    }

    // MARK: Folder access (coordinated, bounded)

    /// A stall either delays the call (shorter than the I/O bound) or makes it time out.
    private mutating func stallOutcome() -> SimReadResult? {
        guard replica.isStalled(at: globalNow) else { return nil }
        let remaining = replica.stalledUntil == Int64.max ? Int64.max : replica.stalledUntil - globalNow
        if remaining > ioTimeoutMilliseconds {
            blockedMilliseconds += ioTimeoutMilliseconds
            return .timedOut
        }
        blockedMilliseconds += remaining
        return nil
    }

    /// A bounded read. A dataless file returns `.notLocal` without content; a partial file returns truncated bytes.
    mutating func read(_ path: String, maximumBytes: Int) -> SimReadResult {
        var wasPartial = false
        if case .partial = replica.entry(path) { wasPartial = true }
        let result = performRead(path, maximumBytes: maximumBytes)
        readLog.append(SimReadLogEntry(path: path, maximumBytes: maximumBytes, result: result, wasPartial: wasPartial))
        return result
    }

    private mutating func performRead(_ path: String, maximumBytes: Int) -> SimReadResult {
        guard folderID != nil else { return .notMounted }
        if let outcome = stallOutcome() { return outcome }
        return replica.read(path, maximumBytes: maximumBytes)
    }

    /// The names inside a directory such as `holzBar/Macs`.
    mutating func list(_ directory: String) -> SimListResult {
        guard folderID != nil, replica.isMounted else { return .notMounted }
        if stallOutcome() != nil { return .timedOut }
        return .names(replica.list(directory))
    }

    /// Writes a file. The Mac sees it at once; the provider delivers it to the other Macs later.
    /// A write on an unmounted folder is still handed to the provider, which records a violation candidate.
    mutating func write(_ path: String, _ data: Data) -> SimWriteResult {
        guard let folderID else { return .notMounted }
        guard replica.isMounted else {
            actions.append(.write(folder: folderID, path: path, data: data))
            return .notMounted
        }
        if stallOutcome() != nil { return .timedOut }
        replica.entries[path] = .present(data)
        replica.versions[path] = -1
        actions.append(.write(folder: folderID, path: path, data: data))
        return .written
    }

    /// Asks the provider to download a dataless file. It becomes present later.
    mutating func requestDownload(_ path: String) {
        guard let folderID else { return }
        actions.append(.requestDownload(folder: folderID, path: path))
    }

    /// The unresolved conflict versions at a path (iCloud `NSFileVersion`), through the coordinated read API.
    mutating func conflictVersions(of path: String) -> [SimFolderReplica.ConflictVersion] {
        guard folderID != nil, replica.isMounted else { return [] }
        if stallOutcome() != nil { return [] }
        return replica.conflictVersions[path] ?? []
    }

    mutating func resolveConflictVersions(of path: String) {
        guard let folderID else { return }
        replica.conflictVersions[path] = nil
        actions.append(.resolveConflictVersions(folder: folderID, path: path))
    }

    // MARK: Crash

    /// The brain calls this after every effect it carries out. When the world asked for a crash
    /// after this many effects, the Mac stops: the answer is `true` and the brain does nothing more.
    mutating func effectRun() -> Bool {
        effectsRun += 1
        if let crashAfterEffects, effectsRun >= crashAfterEffects { crashed = true }
        return crashed
    }

    // MARK: Reports and requests

    mutating func reportIngest(version: Int) { actions.append(.ingest(version: version)) }
    mutating func reportMerge(version: Int) { actions.append(.merged(version: version)) }
    mutating func reportPrompt(_ prompt: SimPrompt) { actions.append(.promptShown(prompt)) }
    mutating func reportAutomaticWrite(unit: String) { actions.append(.automaticWrite(unit: unit)) }
    mutating func scheduleTimer(afterMilliseconds: Int64, tag: String) {
        actions.append(.schedule(afterMilliseconds: afterMilliseconds, tag: tag))
    }
    mutating func cancelTimer(tag: String) { actions.append(.cancelTimer(tag: tag)) }
    /// Asks the world to quit and launch this Mac's app again (for example after "Restart").
    mutating func requestRelaunch() { actions.append(.relaunch) }
    mutating func note(_ text: String) { actions.append(.note(text)) }
}

/// What every Mac kind and the real-engine adapter implement. The world calls the hooks, carries out the
/// actions the context recorded, and asks the read-only queries without a hook.
protocol SimSyncBrain: Sendable {
    var kind: SimMacVersion { get }

    mutating func launch(_ context: inout SimMacContext)
    mutating func quit(_ context: inout SimMacContext)
    /// The process died without running quit code: volatile memory is gone.
    mutating func processDied()
    /// The Mac's preferences or sync state were replaced from outside (a restore, a clone, a lost state): whatever the brain
    /// remembered about waiting changes belongs to a state that is gone.
    mutating func stateWasReplaced()
    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext)
    mutating func folderSignal(_ context: inout SimMacContext)
    mutating func timerFired(tag: String, _ context: inout SimMacContext)
    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext)

    /// The one-line hint the app shows in Settings, if any.
    var hint: String? { get }
    /// The prompt that is open, if any.
    var openPrompt: SimPrompt? { get }
    /// Tokens the brain holds in memory or in its local state although no file or defaults carries them.
    var heldTokens: Set<String> { get }
    /// The tokens a file in the folder carries, decoded by this brain's format (empty for an unknown format).
    func heldTokens(inFile path: String, data: Data) -> Set<String>
    /// The user-change tokens the brain claims a file's context covers; `nil` when the format has no context.
    func claimedPast(ofFile path: String, data: Data) -> Set<String>?
}

extension SimSyncBrain {
    mutating func processDied() {}
    mutating func stateWasReplaced() {}
    var hint: String? { nil }
    var openPrompt: SimPrompt? { nil }
    var heldTokens: Set<String> { [] }
    func claimedPast(ofFile path: String, data: Data) -> Set<String>? { nil }
}

/// A brain for kinds that have no behaviour yet (the redesigned engine before the adapter exists).
struct SimInertBrain: SimSyncBrain {
    var kind: SimMacVersion

    mutating func launch(_ context: inout SimMacContext) {}
    mutating func quit(_ context: inout SimMacContext) {}
    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {}
    mutating func folderSignal(_ context: inout SimMacContext) {}
    mutating func timerFired(tag: String, _ context: inout SimMacContext) {}
    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        // Even an inert Mac keeps its own record of turning sync on or off.
        switch command {
        case .turnOn(let folder), .changeFolder(let folder):
            context.enabled = true
            context.folderID = folder
        case .turnOff:
            context.enabled = false
        default:
            break
        }
    }
    func heldTokens(inFile path: String, data: Data) -> Set<String> { [] }
}
