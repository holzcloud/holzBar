//
//  SyncState.swift
//  holzBar
//

import Foundation

/// Why a unit stays on this Mac: it is not published and remote values do not replace it.
nonisolated enum SyncLocalOnlyReason: String, Hashable, Sendable {
    /// The value is too large to publish.
    case oversize
    /// The value is not valid for the setting.
    case invalid
}

/// How this Mac's current value of a unit came about.
nonisolated enum SyncLocalOrigin: String, Hashable, Sendable {
    /// holzBar wrote it itself, not the user.
    case automatic
    /// It was there before sync was turned on.
    case preexisting
}

/// Where a pending join stands.
nonisolated enum SyncJoinPhase: String, Hashable, Sendable {
    /// Files of the folder are still being read or downloaded; nothing is decided.
    case reading
    /// Every file was read, and the rows of the question wait for an answer.
    case asking
}

/// What the legacy file `holzBar/Settings.plist` offered to a founding join: its settings units
/// (validated and normalized), kept so the question survives a relaunch.
nonisolated struct SyncPendingLegacy: Hashable, Sendable {
    /// The legacy file's synced units.
    var units: [SyncUnitKey: SyncValue]
    /// When the legacy file was written, for display only.
    var modified: Date?
    /// The digest of the legacy file's `(modified, deviceID)`.
    var digest: SyncDigest
}

/// A join that waits for the user: the folder's replica as it was read, which of its
/// differences were shown and whether this Mac is founding the group. It survives a relaunch.
nonisolated struct SyncPendingJoin: Hashable, Sendable {
    /// The tentative state of the folder (joined with this Mac's replica in the same group).
    var replica: SyncReplica
    /// The dots of the values the user has been shown, per unit.
    var shown: [SyncUnitKey: [SyncDot]]
    /// Whether this Mac founds the group, so the folder holds no device file yet.
    var isFounding: Bool
    /// A digest of what identifies the folder, if known.
    var folderIdentity: String?
    /// Whether the files are still being read or the question waits.
    var phase = SyncJoinPhase.reading
    /// Whether this is Change…: Cancel then keeps the previous folder.
    var isChange = false
    /// Whether this Mac's state belongs to the group in the folder (trusted, and some device
    /// file belongs to a Mac it knows); otherwise this Mac's values are dot-less.
    var isSameGroup = false
    /// Whether this Mac's state was trusted when the join started: a relaunch keeps it so, because the
    /// join, not a trust check, decides what the state is worth. A state that is no evidence mints nothing
    /// while the join waits.
    var wasTrusted = false
    /// The legacy file's units when this Mac founds the group from it.
    var legacy: SyncPendingLegacy?
}

/// What this Mac knows about the legacy file `holzBar/Settings.plist` of 0.0.6 and
/// 0.0.7-beta1.
nonisolated struct SyncLegacyRecord: Hashable, Sendable {
    /// `SettingsSyncLastSynced` as this Mac last saw it. holzBar never writes it.
    var lastSyncedSeen: Date?
    /// The digest of the legacy file's `(modified, deviceID)` at founding or joining.
    var foundingDigest: SyncDigest?
    /// The sync ID this Mac had before it re-identified, kept so its own legacy writes are
    /// recognized.
    var legacyDeviceID: String?
    /// When the legacy file last changed after this Mac founded or joined.
    var lastLegacyChange: Date?

    init(lastSyncedSeen: Date? = nil, foundingDigest: SyncDigest? = nil, legacyDeviceID: String? = nil, lastLegacyChange: Date? = nil) {
        self.lastSyncedSeen = lastSyncedSeen
        self.foundingDigest = foundingDigest
        self.legacyDeviceID = legacyDeviceID
        self.lastLegacyChange = lastLegacyChange
    }
}

/// What this Mac last published.
nonisolated struct SyncPublishedRecord: Hashable, Sendable {
    /// The digest of the replica last written to the own device file.
    var replicaDigest: SyncDigest?
    /// The digest of the own file as last read back intact.
    var ownFileDigest: SyncDigest?

    init(replicaDigest: SyncDigest? = nil, ownFileDigest: SyncDigest? = nil) {
        self.replicaDigest = replicaDigest
        self.ownFileDigest = ownFileDigest
    }
}

/// A device file that was refused, as a record that never holds the file's name.
nonisolated struct SyncRefusalRecord: Hashable, Sendable {
    /// The refusal's code (``SyncRefusal/code``).
    var reason: String
    /// The file's size in bytes when it was refused.
    var size: Int
    /// The file's modification date when it was refused.
    var modified: Date?
    /// When this Mac first saw the refusal.
    var firstSeen: Date
}

nonisolated extension SyncRefusal {
    /// A short stable name of the refusal, without any content of the file.
    var code: String {
        switch self {
        case .tooLarge:
            "tooLarge"
        case .notPropertyList:
            "notPropertyList"
        case .wrongStructure:
            "wrongStructure"
        case .newerFormat:
            "newerFormat"
        case .nameMismatch:
            "nameMismatch"
        case .counterOutOfRange:
            "counterOutOfRange"
        case .tooManyEntries:
            "tooManyEntries"
        case .uncoveredEntry:
            "uncoveredEntry"
        case .symbolicLink:
            "symbolicLink"
        case .notRegularFile:
            "notRegularFile"
        case .unreadable:
            "unreadable"
        }
    }
}

/// What this Mac found when it last looked at the own device file in this session.
nonisolated enum SyncOwnFileStatus: Hashable, Sendable {
    /// The own file has not been read in this session (or could not be: dataless, refused, unreadable).
    case unread
    /// The folder was read and held no own file.
    case absent
    /// The own file was read and joined; `digest` is the digest of its replica, and `isDominated`
    /// says the state holds everything the file holds.
    case read(digest: SyncDigest, isDominated: Bool)
}

/// What this Mac knows about the folder in this session. It is never persisted: a relaunch
/// starts with an empty session, so nothing of it is evidence of anything.
nonisolated struct SyncSession: Hashable, Sendable {
    /// Whether Sigma may be used to capture changes. The launch clears it when a trust check
    /// fails (generation, tripwire, identity); the engine then mints nothing.
    var isTrusted = true
    /// What the launch found out about Sigma.
    var trust = SyncTrust()
    /// `SettingsSyncLastSynced` as the defaults held it at launch; a join commit records it.
    var lastSyncedSeen: Date?
    /// The own device file, as last read in this session.
    var ownFile = SyncOwnFileStatus.unread
    /// What the last read said about the folder.
    var availability = SyncFolderAvailability.available
    /// The newest snapshot of the local settings the engine was given. Timers carry none, so
    /// the engine keeps the last one; applying updates it, so a timer never sees a stale value.
    var snapshot: SyncSnapshot?
    /// How many device files are still downloading, or being written by their providers.
    var waitingFiles = 0
    /// How many device files the last read left out because of the file limit.
    var skippedFiles = 0
    /// Whether the replica is too large to write, so the previous own file stays.
    var isTooLargeToPublish = false
    /// The user changes of the macOS 27 families that wait until the state can mint again: a join
    /// is pending, the state is not trusted or capture is deferred. They are never lost, because an
    /// intent cannot be found again by comparing the defaults.
    var queuedIntents: [SyncUnitIntent] = []
    /// Whether the timer that publishes learned applications is running.
    var isLearnedTimerPending = false

    init() {}
}

/// Sigma: this Mac's sync state, one atomic record in
/// `~/Library/Application Support/holzBar/Sync/State.plist`.
///
/// A lost, unreadable or newer Sigma means this Mac is joining. It is never evidence of
/// anything: no unit is removed, replaced or published because Sigma says nothing.
nonisolated struct SyncState: Hashable, Sendable {
    /// The state format this build reads and writes.
    static let currentFormat = 1

    /// The state format.
    var format: Int
    /// This Mac's identity.
    var mac: SyncMacID
    /// The nonce of this installation, changed when the Mac re-identifies.
    var nonce: String
    /// The last counter this Mac used.
    var counter: UInt64
    /// ``counter`` at the last own-file write that read back intact. Dots above it are
    /// unpublished.
    var publishedCounter: UInt64
    /// Increases with every persist; mirrored to the defaults before Sigma is persisted.
    var generation: UInt64
    /// The context plus the current entries this Mac holds.
    var replica: SyncReplica
    /// The dots whose value the defaults hold, per unit.
    var applied: [SyncUnitKey: [SyncDot]]
    /// The digest of the local value as last captured or applied, per unit; a missing unit
    /// has no baseline, ``SyncDigest/unset`` marks a captured absent value.
    var baseline: [SyncUnitKey: SyncDigest]
    /// Units that are not published and not replaced by remote values.
    var localOnly: [SyncUnitKey: SyncLocalOnlyReason]
    /// How the local value of a unit came about.
    var localOrigin: [SyncUnitKey: SyncLocalOrigin]
    /// A pending join, if any.
    var pendingJoin: SyncPendingJoin?
    /// What this Mac knows about the legacy file.
    var legacy: SyncLegacyRecord
    /// What this Mac last published.
    var published: SyncPublishedRecord
    /// The launch count at the last "Later".
    var laterLaunch: UInt64?
    /// How often holzBar has launched with sync on.
    var launchCount: UInt64
    /// Refused device files, keyed by the identity of the Mac whose file it is, never by a
    /// raw file name.
    var refusals: [String: SyncRefusalRecord]
    /// The identities this Mac had before it re-identified.
    var previousMacIDs: [SyncMacID]
    /// Whether sync is turned on.
    var isEnabled: Bool
    /// Whether capture waits until the own file was read and joined: Sigma was behind the
    /// defaults at launch (it was restored alone, or a crash kept it from being written), so
    /// it may not know this Mac's own later writes.
    var captureDeferred = false
    /// The macOS generation of the last launch, so an upgrade from macOS 26 to 27 is recognised;
    /// `nil` in a state written before it was recorded.
    var systemGeneration: SyncGeneration?
    /// What this Mac knows about the folder in this session; not part of Sigma on disk.
    var session = SyncSession()

    init(
        mac: SyncMacID,
        nonce: String,
        counter: UInt64 = 0,
        publishedCounter: UInt64 = 0,
        generation: UInt64 = 0,
        replica: SyncReplica = .empty,
        isEnabled: Bool = false
    ) {
        format = Self.currentFormat
        self.mac = mac
        self.nonce = nonce
        self.counter = counter
        self.publishedCounter = publishedCounter
        self.generation = generation
        self.replica = replica
        applied = [:]
        baseline = [:]
        localOnly = [:]
        localOrigin = [:]
        pendingJoin = nil
        legacy = SyncLegacyRecord()
        published = SyncPublishedRecord()
        laterLaunch = nil
        launchCount = 0
        refusals = [:]
        previousMacIDs = []
        self.isEnabled = isEnabled
    }
}

/// What reading Sigma gives.
nonisolated enum SyncStateDecodeResult: Hashable, Sendable {
    /// A valid state.
    case state(SyncState)
    /// Damaged, truncated or of the wrong shape: treated as no state.
    case unreadable
    /// Written by a newer format, whose number it carries: never rewritten.
    case newerFormat(Int)
}

/// Writes and reads Sigma as a binary property list.
nonisolated enum SyncStateCodec {
    /// The largest state file read. It holds the replica and some bookkeeping.
    static let maximumSize = 8 << 20

    // MARK: Encoding

    static func encode(_ state: SyncState) throws -> Data {
        var root: [String: Any] = ["replica": SyncDeviceFile.replicaFields(state.replica)]
        root["format"] = state.format
        root["mac"] = state.mac.rawValue
        root["nonce"] = state.nonce
        root["counter"] = Int64(clamping: state.counter)
        root["publishedCounter"] = Int64(clamping: state.publishedCounter)
        root["generation"] = Int64(clamping: state.generation)
        root["applied"] = state.applied.keys.sorted().map { key -> [String: Any] in
            ["unit": unitFields(key), "dots": (state.applied[key] ?? []).sorted().map(dotFields)]
        }
        root["baseline"] = state.baseline.keys.sorted().map { key -> [String: Any] in
            ["unit": unitFields(key), "digest": state.baseline[key]?.hex ?? ""]
        }
        root["localOnly"] = state.localOnly.keys.sorted().map { key -> [String: Any] in
            ["unit": unitFields(key), "reason": state.localOnly[key]?.rawValue ?? ""]
        }
        root["localOrigin"] = state.localOrigin.keys.sorted().map { key -> [String: Any] in
            ["unit": unitFields(key), "origin": state.localOrigin[key]?.rawValue ?? ""]
        }
        if let pending = state.pendingJoin {
            var fields: [String: Any] = [
                "replica": SyncDeviceFile.replicaFields(pending.replica),
                "shown": pending.shown.keys.sorted().map { key -> [String: Any] in
                    ["unit": unitFields(key), "dots": (pending.shown[key] ?? []).sorted().map(dotFields)]
                },
                "isFounding": pending.isFounding,
                "phase": pending.phase.rawValue,
                "isChange": pending.isChange,
                "isSameGroup": pending.isSameGroup,
                "wasTrusted": pending.wasTrusted,
            ]
            fields["folderIdentity"] = pending.folderIdentity
            if let legacy = pending.legacy {
                var record: [String: Any] = [
                    "units": legacy.units.keys.sorted().map { key -> [String: Any] in
                        ["unit": unitFields(key), "value": legacy.units[key]?.propertyList ?? ""]
                    },
                    "digest": legacy.digest.hex,
                ]
                record["modified"] = legacy.modified
                fields["legacy"] = record
            }
            root["pendingJoin"] = fields
        }
        var legacy: [String: Any] = [:]
        legacy["lastSyncedSeen"] = state.legacy.lastSyncedSeen
        legacy["foundingDigest"] = state.legacy.foundingDigest?.hex
        legacy["legacyDeviceID"] = state.legacy.legacyDeviceID
        legacy["lastLegacyChange"] = state.legacy.lastLegacyChange
        root["legacy"] = legacy
        var published: [String: Any] = [:]
        published["replicaDigest"] = state.published.replicaDigest?.hex
        published["ownFileDigest"] = state.published.ownFileDigest?.hex
        root["published"] = published
        root["laterLaunch"] = state.laterLaunch.map { Int64(clamping: $0) }
        root["launchCount"] = Int64(clamping: state.launchCount)
        var refusals: [String: Any] = [:]
        for name in state.refusals.keys.sorted() {
            guard let record = state.refusals[name] else {
                continue
            }
            var fields: [String: Any] = ["reason": record.reason, "size": record.size, "firstSeen": record.firstSeen]
            fields["modified"] = record.modified
            refusals[name] = fields
        }
        root["refusals"] = refusals
        root["previousMacIDs"] = state.previousMacIDs.map(\.rawValue)
        root["isEnabled"] = state.isEnabled
        if state.captureDeferred {
            root["captureDeferred"] = true
        }
        if let generation = state.systemGeneration {
            root["systemGeneration"] = generation == .g27 ? 27 : 26
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private static func unitFields(_ key: SyncUnitKey) -> [String: Any] {
        switch key {
        case .whole(let name):
            ["unit": name]
        case .split(let family, let item):
            ["family": family, "item": item]
        }
    }

    private static func dotFields(_ dot: SyncDot) -> [String: Any] {
        ["mac": dot.mac.rawValue, "n": Int64(clamping: dot.n)]
    }

    // MARK: Decoding

    /// Reads Sigma. Anything that is not a state this build can read in full is
    /// ``SyncStateDecodeResult/unreadable``, never an empty state.
    static func decode(_ data: Data) -> SyncStateDecodeResult {
        guard data.count <= maximumSize else {
            return .unreadable
        }
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let root = object as? [String: Any]
        else {
            return .unreadable
        }
        guard let format = root["format"].flatMap({ SyncValue(propertyList: $0) })?.integerValue, format >= 1 else {
            return .unreadable
        }
        guard format <= SyncState.currentFormat else {
            return .newerFormat(Int(clamping: format))
        }
        guard let top = SyncValue(propertyList: root)?.dictionaryValue else {
            return .unreadable
        }
        do throws(SyncRefusal) {
            return .state(try state(top))
        } catch {
            return .unreadable
        }
    }

    private static func state(_ top: [String: SyncValue]) throws(SyncRefusal) -> SyncState {
        guard let mac = SyncMacID(try string(top, "mac")) else {
            throw .wrongStructure("mac")
        }
        var state = SyncState(mac: mac, nonce: try string(top, "nonce"))
        state.counter = try unsigned(top, "counter")
        state.publishedCounter = try unsigned(top, "publishedCounter")
        state.generation = try unsigned(top, "generation")
        state.replica = try SyncDeviceFile.decodeReplica(try dictionary(top, "replica"))
        for element in try list(top, "applied") {
            let fields = try record(element)
            state.applied[try unit(fields)] = try dots(fields)
        }
        for element in try list(top, "baseline") {
            let fields = try record(element)
            state.baseline[try unit(fields)] = SyncDigest(hex: try string(fields, "digest"))
        }
        for element in try list(top, "localOnly") {
            let fields = try record(element)
            guard let reason = SyncLocalOnlyReason(rawValue: try string(fields, "reason")) else {
                throw .wrongStructure("localOnly")
            }
            state.localOnly[try unit(fields)] = reason
        }
        for element in try list(top, "localOrigin") {
            let fields = try record(element)
            guard let origin = SyncLocalOrigin(rawValue: try string(fields, "origin")) else {
                throw .wrongStructure("localOrigin")
            }
            state.localOrigin[try unit(fields)] = origin
        }
        if let pending = top["pendingJoin"] {
            let fields = try record(pending)
            var shown: [SyncUnitKey: [SyncDot]] = [:]
            for element in try list(fields, "shown") {
                let entry = try record(element)
                shown[try unit(entry)] = try dots(entry)
            }
            var pendingJoin = SyncPendingJoin(
                replica: try SyncDeviceFile.decodeReplica(try dictionary(fields, "replica")),
                shown: shown,
                isFounding: try bool(fields, "isFounding"),
                folderIdentity: try optionalString(fields, "folderIdentity")
            )
            // Fields that came after the first version of this format: a pending join written
            // without them is a question that waits.
            if let phase = try optionalString(fields, "phase") {
                guard let known = SyncJoinPhase(rawValue: phase) else {
                    throw .wrongStructure("phase")
                }
                pendingJoin.phase = known
            } else {
                pendingJoin.phase = .asking
            }
            pendingJoin.isChange = try optionalBool(fields, "isChange") ?? false
            pendingJoin.isSameGroup = try optionalBool(fields, "isSameGroup") ?? false
            pendingJoin.wasTrusted = try optionalBool(fields, "wasTrusted") ?? false
            if let legacy = fields["legacy"] {
                let legacyFields = try record(legacy)
                var units: [SyncUnitKey: SyncValue] = [:]
                for element in try list(legacyFields, "units") {
                    let entry = try record(element)
                    guard let value = entry["value"] else {
                        throw .wrongStructure("legacy")
                    }
                    units[try unit(entry)] = value
                }
                pendingJoin.legacy = SyncPendingLegacy(
                    units: units,
                    modified: try optionalDate(legacyFields, "modified"),
                    digest: SyncDigest(hex: try string(legacyFields, "digest"))
                )
            }
            state.pendingJoin = pendingJoin
        }
        let legacy = try dictionary(top, "legacy")
        state.legacy = SyncLegacyRecord(
            lastSyncedSeen: try optionalDate(legacy, "lastSyncedSeen"),
            foundingDigest: try optionalString(legacy, "foundingDigest").map { SyncDigest(hex: $0) },
            legacyDeviceID: try optionalString(legacy, "legacyDeviceID"),
            lastLegacyChange: try optionalDate(legacy, "lastLegacyChange")
        )
        let published = try dictionary(top, "published")
        state.published = SyncPublishedRecord(
            replicaDigest: try optionalString(published, "replicaDigest").map { SyncDigest(hex: $0) },
            ownFileDigest: try optionalString(published, "ownFileDigest").map { SyncDigest(hex: $0) }
        )
        if top["laterLaunch"] != nil {
            state.laterLaunch = try unsigned(top, "laterLaunch")
        }
        state.launchCount = try unsigned(top, "launchCount")
        let refusals = try dictionary(top, "refusals")
        for name in refusals.keys.sorted() {
            let fields = try record(refusals[name])
            guard let size = Int(exactly: try integer(fields, "size")), let firstSeen = fields["firstSeen"]?.dateValue else {
                throw .wrongStructure("refusals")
            }
            state.refusals[name] = SyncRefusalRecord(
                reason: try string(fields, "reason"),
                size: size,
                modified: try optionalDate(fields, "modified"),
                firstSeen: firstSeen
            )
        }
        state.previousMacIDs = try list(top, "previousMacIDs").map { element throws(SyncRefusal) in
            guard let id = element.stringValue.flatMap({ SyncMacID($0) }) else {
                throw .wrongStructure("previousMacIDs")
            }
            return id
        }
        state.isEnabled = try bool(top, "isEnabled")
        state.captureDeferred = try optionalBool(top, "captureDeferred") ?? false
        if top["systemGeneration"] != nil {
            state.systemGeneration = try integer(top, "systemGeneration") >= 27 ? .g27 : .g26
        }
        return state
    }

    // MARK: Readers

    private static func record(_ value: SyncValue?) throws(SyncRefusal) -> [String: SyncValue] {
        guard let fields = value?.dictionaryValue else {
            throw .wrongStructure("record")
        }
        return fields
    }

    private static func dictionary(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> [String: SyncValue] {
        guard let value = fields[key]?.dictionaryValue else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func list(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> [SyncValue] {
        guard let value = fields[key]?.arrayValue else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func string(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> String {
        guard let value = fields[key]?.stringValue else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func optionalString(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> String? {
        guard let value = fields[key] else {
            return nil
        }
        guard let string = value.stringValue else {
            throw .wrongStructure(key)
        }
        return string
    }

    private static func optionalDate(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> Date? {
        guard let value = fields[key] else {
            return nil
        }
        guard let date = value.dateValue else {
            throw .wrongStructure(key)
        }
        return date
    }

    private static func optionalBool(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> Bool? {
        guard let value = fields[key] else {
            return nil
        }
        guard let flag = value.boolValue else {
            throw .wrongStructure(key)
        }
        return flag
    }

    private static func bool(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> Bool {
        guard let value = fields[key]?.boolValue else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func integer(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> Int64 {
        guard let value = fields[key]?.integerValue else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func unsigned(_ fields: [String: SyncValue], _ key: String) throws(SyncRefusal) -> UInt64 {
        guard let value = UInt64(exactly: try integer(fields, key)) else {
            throw .wrongStructure(key)
        }
        return value
    }

    private static func unit(_ fields: [String: SyncValue]) throws(SyncRefusal) -> SyncUnitKey {
        let key = try dictionary(fields, "unit")
        if let family = key["family"]?.stringValue, let item = key["item"]?.stringValue {
            return .split(family: family, item: item)
        }
        if let name = key["unit"]?.stringValue {
            return .whole(name)
        }
        throw .wrongStructure("unit")
    }

    private static func dots(_ fields: [String: SyncValue]) throws(SyncRefusal) -> [SyncDot] {
        try list(fields, "dots").map { element throws(SyncRefusal) in
            let dot = try record(element)
            guard let mac = SyncMacID(try string(dot, "mac")) else {
                throw .wrongStructure("dots")
            }
            return SyncDot(mac: mac, n: try unsigned(dot, "n"))
        }
    }
}
