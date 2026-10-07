//
//  SyncEngine.swift
//  holzBar
//

import Foundation

// MARK: - Inputs

/// The local settings as the engine sees them: the projected, normalized value of every synced
/// unit that is present in the defaults (``SyncProjection/snapshot(defaults:table:generation:)``),
/// plus the units this Mac maps to another key (`ItemIdentity.storedKey`).
nonisolated struct SyncSnapshot: Hashable, Sendable {
    /// The present values, normalized. An absent unit is not in the dictionary.
    var values: [SyncUnitKey: SyncValue]
    /// The units whose key this Mac maps to another key: relayed only, never captured as a
    /// deletion and never applied (analysis section 4.6.2, the alias rule).
    var aliased: Set<SyncUnitKey>

    init(values: [SyncUnitKey: SyncValue] = [:], aliased: Set<SyncUnitKey> = []) {
        self.values = values
        self.aliased = aliased
    }

    /// The snapshot after the defaults took `changes`: what the engine itself applied, so a
    /// timer never captures a value the engine just wrote as if the user had changed it.
    func applying(_ changes: [SyncUnitKey: SyncPayload], table: SyncUnitTable) -> SyncSnapshot {
        var result = self
        for key in changes.keys.sorted() {
            guard let payload = changes[key] else {
                continue
            }
            switch payload {
            case .deleted:
                result.values[key] = nil
            case .value(let value):
                let normalized = table.normalized(value, for: key)
                if case .split(let family, _) = key, family == SyncUnitTable.layout27Family, normalized == .integer(0) {
                    // Visible is the absence of a stored section.
                    result.values[key] = nil
                } else {
                    result.values[key] = normalized
                }
            }
        }
        return result
    }
}

/// The defenses of the engine that the simulator can remove one at a time to build a control
/// engine (analysis section 5.6). The app always passes ``all``.
nonisolated struct SyncGuards: OptionSet, Sendable {
    let rawValue: Int

    /// A local change supersedes only the dots this Mac had applied (analysis section 4.6.2).
    static let appliedContext = SyncGuards(rawValue: 1 << 0)
    /// The own file is written only after it was read in this session and is dominated.
    static let ownFileReadFirst = SyncGuards(rawValue: 1 << 1)
    /// Capture mints only while the state is trusted (analysis section 4.6.6).
    static let trustedState = SyncGuards(rawValue: 1 << 2)
    /// A unit that was never present is never captured as a deletion (decision D-10).
    static let absentMeansNoValue = SyncGuards(rawValue: 1 << 3)

    /// Every defense.
    static let all: SyncGuards = [.appliedContext, .ownFileReadFirst, .trustedState, .absentMeansNoValue]
}

/// The counters outside Sigma that the next counter must stay above.
nonisolated struct SyncCounterFloors: Hashable, Sendable {
    /// The counter mirror in the defaults (`SettingsSyncCounter`).
    var mirror: UInt64
    /// The high-water mark in the Caches folder.
    var highWater: UInt64

    init(mirror: UInt64 = 0, highWater: UInt64 = 0) {
        self.mirror = mirror
        self.highWater = highWater
    }
}

/// A new identity for this Mac. The engine uses no randomness, so the host draws it.
nonisolated struct SyncFreshIdentity: Hashable, Sendable {
    var mac: SyncMacID
    var nonce: String
}

/// Everything the engine may know about the world besides the event and the state. The engine
/// reads no clock and draws no random number: the host supplies both here.
nonisolated struct SyncEnvironment: Sendable {
    /// The unit table.
    var table: SyncUnitTable
    /// The macOS generation of this Mac.
    var generation: SyncGeneration
    /// The host's clock. It fills display fields, and decides only how long a refusal has
    /// lasted (ten minutes) and how long the legacy status line shows (30 days); never a value.
    var now: Date
    /// The host's clock in whole unix seconds: a floor of the next counter.
    var unixSeconds: UInt64
    /// The counters outside Sigma.
    var counterFloors: SyncCounterFloors
    /// The defenses; the app passes ``SyncGuards/all``.
    var guards: SyncGuards
    /// A fresh unused identity the engine takes when it has to re-identify this Mac. Without
    /// one, a file that calls for re-identification is left out of the join.
    var freshIdentity: SyncFreshIdentity?

    init(
        table: SyncUnitTable,
        generation: SyncGeneration,
        now: Date,
        unixSeconds: UInt64,
        counterFloors: SyncCounterFloors = SyncCounterFloors(),
        guards: SyncGuards = .all,
        freshIdentity: SyncFreshIdentity? = nil
    ) {
        self.table = table
        self.generation = generation
        self.now = now
        self.unixSeconds = unixSeconds
        self.counterFloors = counterFloors
        self.guards = guards
        self.freshIdentity = freshIdentity
    }
}

// MARK: - Events

/// A timer the engine asks the host to run, one pending timer per kind.
nonisolated enum SyncTimer: Hashable, Sendable {
    /// Two seconds after the last change of the defaults: capture and publish.
    case capture
    /// Ten seconds after a merge changed the replica: relay other Macs' values.
    case relay
    /// Two seconds after a trigger of the folder: read it.
    case check
    /// The slow poll of the folder.
    case periodic
    /// Two seconds after the own file turned out to be missing, older or damaged.
    case healing

    /// How long the host waits before it fires the timer.
    var delay: TimeInterval {
        switch self {
        case .capture, .check, .healing:
            2
        case .relay:
            10
        case .periodic:
            15 * 60
        }
    }
}

/// Why the host reads the folder.
nonisolated enum SyncReadPurpose: Hashable, Sendable {
    /// A background or triggered check, or the poll.
    case check
    /// The read at launch.
    case launch
    /// The read of a join (plan 28-08).
    case join
}

/// What the user asks of the engine.
nonisolated enum SyncCommand: Hashable, Sendable {
    /// Apply what waits and relaunch.
    case restart
}

/// What happened.
nonisolated enum SyncEvent: Sendable {
    /// The defaults changed (or the app started): the new snapshot. Capture runs after a debounce.
    case defaultsChanged(SyncSnapshot)
    /// The host read the folder.
    case folderRead(SyncFolderRead, purpose: SyncReadPurpose)
    /// The host finished a write.
    case writeFinished(SyncWriteResult)
    /// A timer the engine scheduled fired.
    case timer(SyncTimer)
    /// The user gave a command.
    case command(SyncCommand)
    /// The app quits: the last snapshot.
    case quit(SyncSnapshot)
}

// MARK: - Folder reads

/// Whether the sync folder can be used.
nonisolated enum SyncFolderAvailability: Hashable, Sendable {
    /// The folder and `holzBar/Macs/` can be listed.
    case available
    /// Not found, or not mounted.
    case unavailable
    /// A link or a file where a folder must be.
    case unusable
}

/// What the host found for one device file.
nonisolated enum SyncFileState: Hashable, Sendable {
    /// The file was read and decoded.
    case contents(SyncDeviceFile.Contents)
    /// The file was read and refused whole.
    case refused(SyncRefusal)
    /// The content is not on this Mac yet.
    case dataless
    /// The file is still being written or downloaded, or the read stalled.
    case pending
    /// A conflict copy of the device file of `owner`; its content is never read.
    case conflictCopy(owner: SyncMacID)
}

/// One device file of a read. The engine never sees a file name: a name can hold a computer
/// name and is never logged.
nonisolated struct SyncFileOutcome: Hashable, Sendable {
    /// The Mac the file belongs to; `nil` for a conflict copy.
    var macID: SyncMacID?
    /// The file's size in bytes.
    var size: Int
    /// The file's modification date, if the host knows it.
    var modified: Date?
    var state: SyncFileState

    init(macID: SyncMacID?, size: Int = 0, modified: Date? = nil, state: SyncFileState) {
        self.macID = macID
        self.size = size
        self.modified = modified
        self.state = state
    }
}

/// What the host found of the legacy file `holzBar/Settings.plist`.
nonisolated enum SyncLegacyOutcome: Hashable, Sendable {
    /// There is no legacy file.
    case absent
    /// The file was read; for a metadata request its settings are empty.
    case file(SyncLegacyFile)
    /// The file was read and refused.
    case refused(SyncRefusal)
}

/// What the host asks for the legacy file.
nonisolated enum SyncLegacyRequest: Hashable, Sendable {
    /// Do not look at it.
    case none
    /// Only when it was written and by whom.
    case metadata
    /// Its settings, to found a group from them (plan 28-08).
    case settings
}

/// What the engine asks the host to read.
nonisolated struct SyncReadRequest: Hashable, Sendable {
    var purpose: SyncReadPurpose
    var legacy: SyncLegacyRequest
    /// The Macs whose conflict copies are recognized by name.
    var knownMacs: [SyncMacID]
    /// The most device files read: the most recently modified, then by name.
    var maximumFiles: Int

    init(purpose: SyncReadPurpose, legacy: SyncLegacyRequest = .none, knownMacs: [SyncMacID] = [], maximumFiles: Int = SyncReadRequest.defaultMaximumFiles) {
        self.purpose = purpose
        self.legacy = legacy
        self.knownMacs = knownMacs
        self.maximumFiles = maximumFiles
    }

    /// The most device files read per check (analysis section 4.3).
    static let defaultMaximumFiles = 64
}

/// What one read of the folder found.
nonisolated struct SyncFolderRead: Hashable, Sendable {
    var availability: SyncFolderAvailability
    var files: [SyncFileOutcome]
    var legacy: SyncLegacyOutcome?
    /// How many device files the host left out because of the file limit.
    var skipped: Int

    init(availability: SyncFolderAvailability = .available, files: [SyncFileOutcome] = [], legacy: SyncLegacyOutcome? = nil, skipped: Int = 0) {
        self.availability = availability
        self.files = files
        self.legacy = legacy
        self.skipped = skipped
    }
}

// MARK: - Effects

/// What the host must persist before it writes any file.
nonisolated struct SyncPersist: Hashable, Sendable {
    /// The generation to store in the defaults (`SettingsSyncGeneration`) first.
    var generation: UInt64
    /// The counter to mirror in the defaults and in the Caches folder, then Sigma.
    var counter: UInt64
}

/// What the engine asks the host to do, always in execution order.
nonisolated enum SyncEffect: Sendable {
    /// Write these payloads to the defaults (``SyncProjection/defaultsWrites(applying:to:table:)``).
    case applyUnits([SyncUnitKey: SyncPayload])
    /// Persist the generation, the counter mirror and Sigma, in this order.
    case persist(SyncPersist)
    case readFolder(SyncReadRequest)
    case writeOwnFile(SyncWriteRequest)
    /// Run the timer after the delay; it replaces a pending timer of the same kind, so a burst
    /// of triggers fires once.
    case schedule(SyncTimer, after: TimeInterval)
    case cancelTimer(SyncTimer)
    /// Quit and launch holzBar again.
    case relaunch
    /// Ask the provider to download these Macs' files.
    case requestDownload(macs: [SyncMacID])
}

/// The new state and what the host must do.
nonisolated struct SyncStep: Sendable {
    var state: SyncState
    var effects: [SyncEffect]
}

// MARK: - View

/// The one hint the app shows.
nonisolated enum SyncHint: Hashable, Sendable {
    /// Settings changed on another Mac and wait for a restart.
    case restart
    /// A question of this Mac's, a clash or a pre row waits.
    case choose
    /// A join has rows.
    case chooseAfterJoin
}

/// One line of the sync status in Settings.
nonisolated enum SyncStatusLine: Hashable, Sendable {
    case joining(waitingFiles: Int)
    case bystander(rows: Int)
    case waitingFiles(Int)
    case newerFormat
    case olderHolzBar
    case oversizeIcon
    case unreadableFile
    case unusableValue
    case skippedFiles(Int)
    /// This Mac's settings are too large to write; the previous file stays.
    case tooLargeToPublish
}

/// What the app shows of the state.
nonisolated struct SyncView: Hashable, Sendable {
    var hint: SyncHint?
    var lines: [SyncStatusLine]
}

// MARK: - Engine

/// The decision core of the redesigned settings sync: one entry point, pure transitions.
///
/// An event, the state and the environment go in; the new state and an ordered list of effects
/// come out. The engine does no I/O, reads no clock, uses no randomness and iterates every
/// dictionary and set sorted, so one input gives one output.
nonisolated enum SyncEngine {
    /// How long the legacy status line shows after the legacy file last changed.
    static let legacyDisplayHorizon: TimeInterval = 30 * 24 * 3600

    /// What a draft of a step holds while the engine decides.
    private struct Draft {
        let original: SyncState
        var state: SyncState
        var applies: [SyncUnitKey: SyncPayload] = [:]
        var effects: [SyncEffect] = []

        init(_ state: SyncState) {
            original = state
            self.state = state
        }

        /// The step: applies first, then the persist when anything persistent changed, then the
        /// rest, so Sigma is persisted before any file is written.
        mutating func finish() -> SyncStep {
            var list: [SyncEffect] = []
            if !applies.isEmpty {
                list.append(.applyUnits(applies))
            }
            if !applies.isEmpty || state.differsPersistently(from: original) {
                state.generation = original.generation + 1
                list.append(.persist(SyncPersist(generation: state.generation, counter: state.counter)))
            }
            list += effects
            return SyncStep(state: state, effects: list)
        }
    }

    static func handle(_ event: SyncEvent, state: SyncState, environment: SyncEnvironment) -> SyncStep {
        var draft = Draft(state)
        switch event {
        case .defaultsChanged(let snapshot):
            draft.state.session.snapshot = snapshot
            if state.isEnabled {
                draft.effects.append(.schedule(.capture, after: SyncTimer.capture.delay))
            }
        case .quit(let snapshot):
            draft.state.session.snapshot = snapshot
            if state.isEnabled {
                capture(&draft, environment: environment)
                publish(&draft, trigger: .quit, environment: environment)
            }
        case .timer(let timer):
            guard state.isEnabled else {
                break
            }
            onTimer(timer, &draft, environment: environment)
        case .folderRead(let read, let purpose):
            guard state.isEnabled else {
                break
            }
            onRead(read, purpose: purpose, &draft, environment: environment)
        case .writeFinished(let result):
            onWrite(result, &draft)
        case .command(.restart):
            guard state.isEnabled else {
                break
            }
            restart(&draft, environment: environment)
        }
        return draft.finish()
    }

    // MARK: Timers

    private static func onTimer(_ timer: SyncTimer, _ draft: inout Draft, environment: SyncEnvironment) {
        switch timer {
        case .capture:
            capture(&draft, environment: environment)
            publish(&draft, trigger: .ownChange, environment: environment)
        case .relay:
            publish(&draft, trigger: .relay, environment: environment)
        case .healing:
            publish(&draft, trigger: .healing, environment: environment)
        case .check:
            draft.effects.append(.readFolder(readRequest(.check, draft.state)))
        case .periodic:
            draft.effects.append(.readFolder(readRequest(.check, draft.state)))
            draft.effects.append(.schedule(.periodic, after: SyncTimer.periodic.delay))
        }
    }

    private static func readRequest(_ purpose: SyncReadPurpose, _ state: SyncState) -> SyncReadRequest {
        // The legacy file's settings are read only to found a group (plan 28-08); afterwards
        // only its metadata, for the status line.
        let legacy: SyncLegacyRequest = state.legacy.foundingDigest == nil ? .none : .metadata
        var macs = Set(state.replica.context.macs)
        macs.formUnion(state.previousMacIDs)
        macs.insert(state.mac)
        return SyncReadRequest(purpose: purpose, legacy: legacy, knownMacs: macs.sorted())
    }

    // MARK: Capture and publish

    private static func capture(_ draft: inout Draft, environment: SyncEnvironment) {
        guard let snapshot = draft.state.session.snapshot else {
            return
        }
        draft.state = SyncCapture.capture(snapshot, state: draft.state, environment: environment)
    }

    /// Asks the publish rules and, when they say write, emits the write.
    private static func publish(_ draft: inout Draft, trigger: SyncWriteTrigger, environment: SyncEnvironment) {
        switch SyncPublish.decision(state: draft.state, environment: environment, trigger: trigger) {
        case .write(let request):
            draft.state.session.isTooLargeToPublish = false
            draft.effects.append(.writeOwnFile(request))
        case .none(.tooLarge):
            draft.state.session.isTooLargeToPublish = true
        case .none:
            break
        }
    }

    private static func onWrite(_ result: SyncWriteResult, _ draft: inout Draft) {
        draft.state = SyncPublish.apply(result, to: draft.state)
        if case .failed(.ownFileChanged) = result {
            // The own file is not what this session read: read it again before any write.
            draft.effects.append(.schedule(.check, after: SyncTimer.check.delay))
        }
    }

    // MARK: Reads

    private static func onRead(_ read: SyncFolderRead, purpose: SyncReadPurpose, _ draft: inout Draft, environment: SyncEnvironment) {
        // A change made while the folder was away still counts: capture first, then merge.
        capture(&draft, environment: environment)
        let merged = SyncMerge.merge(read, into: draft.state, environment: environment)
        draft.state = merged.state
        if let snapshot = draft.state.session.snapshot {
            let plan = SyncPlan.plan(state: draft.state, snapshot: snapshot, environment: environment)
            draft.state = SyncCapture.settle(plan, snapshot: snapshot, state: draft.state, environment: environment)
        }
        if !merged.downloads.isEmpty {
            draft.effects.append(.requestDownload(macs: merged.downloads))
        }
        guard case .write = SyncPublish.decision(state: draft.state, environment: environment, trigger: .relay) else {
            return
        }
        if merged.needsHealing || merged.reidentified {
            draft.effects.append(.schedule(.healing, after: SyncTimer.healing.delay))
        } else {
            draft.effects.append(.schedule(.relay, after: SyncTimer.relay.delay))
        }
    }

    // MARK: Restart

    private static func restart(_ draft: inout Draft, environment: SyncEnvironment) {
        // A change made just before Restart still counts (S-64).
        capture(&draft, environment: environment)
        if let snapshot = draft.state.session.snapshot {
            let plan = SyncPlan.plan(state: draft.state, snapshot: snapshot, environment: environment)
            draft.state = SyncCapture.settle(plan, snapshot: snapshot, state: draft.state, environment: environment)
            let changes = plan.fastForwardPayloads
            if !changes.isEmpty {
                draft.applies = changes
                draft.state = SyncCapture.applied(changes, snapshot: snapshot, state: draft.state, environment: environment)
            }
        }
        publish(&draft, trigger: .ownChange, environment: environment)
        draft.effects.append(.relaunch)
    }

    // MARK: View

    /// What the app shows of `state`: the hint and the status lines, computed from the
    /// persisted replica, the last snapshot and the session.
    static func view(of state: SyncState, environment: SyncEnvironment) -> SyncView {
        let plan = state.session.snapshot.map { SyncPlan.plan(state: state, snapshot: $0, environment: environment) }
        var lines: [SyncStatusLine] = []
        if state.pendingJoin != nil {
            lines.append(.joining(waitingFiles: state.session.waitingFiles))
        } else if state.session.waitingFiles > 0 {
            lines.append(.waitingFiles(state.session.waitingFiles))
        }
        if state.refusals.values.contains(where: { $0.reason == SyncRefusal.newerFormat(0).code }) {
            lines.append(.newerFormat)
        }
        if state.refusals.values.contains(where: { $0.reason != SyncRefusal.newerFormat(0).code }) {
            lines.append(.unreadableFile)
        }
        if let change = state.legacy.lastLegacyChange, environment.now.timeIntervalSince(change) < legacyDisplayHorizon {
            lines.append(.olderHolzBar)
        }
        if state.localOnly[.whole(SyncUnitTable.holzBarIconUnit)] == .oversize {
            lines.append(.oversizeIcon)
        }
        if state.session.isTooLargeToPublish {
            lines.append(.tooLargeToPublish)
        }
        if let plan {
            if plan.hasUnusableValue {
                lines.append(.unusableValue)
            }
            if plan.bystanderRows > 0 {
                lines.append(.bystander(rows: plan.bystanderRows))
            }
        }
        if state.session.skippedFiles > 0 {
            lines.append(.skippedFiles(state.session.skippedFiles))
        }
        let hint: SyncHint? = if state.pendingJoin != nil {
            .chooseAfterJoin
        } else {
            plan?.hint
        }
        return SyncView(hint: hint, lines: lines)
    }
}

nonisolated extension SyncState {
    /// Whether anything differs that Sigma holds on disk; the session never counts.
    func differsPersistently(from other: SyncState) -> Bool {
        var left = self
        left.session = SyncSession()
        var right = other
        right.session = SyncSession()
        return left != right
    }

    /// Whether `mac` is this Mac's current identity or one it had before.
    func isOwn(_ mac: SyncMacID) -> Bool {
        mac == self.mac || previousMacIDs.contains(mac)
    }
}
