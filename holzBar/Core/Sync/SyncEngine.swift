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
    /// The local `KnownApplications27`, sorted and unique; empty before macOS 27.
    var known27: [String]

    init(values: [SyncUnitKey: SyncValue] = [:], aliased: Set<SyncUnitKey> = [], known27: [String] = []) {
        self.values = values
        self.aliased = aliased
        self.known27 = known27
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
    /// An hour after this Mac learned an application: a learned-only change is published at the
    /// latest then, or rides along with the next write.
    case learned

    /// How long the host waits before it fires the timer.
    var delay: TimeInterval {
        switch self {
        case .capture, .check, .healing:
            2
        case .relay:
            10
        case .periodic:
            15 * 60
        case .learned:
            60 * 60
        }
    }
}

/// Why the host reads the folder.
nonisolated enum SyncReadPurpose: Hashable, Sendable {
    /// A background or triggered check, or the poll.
    case check
    /// The read at launch, which the host bounds to `budget` seconds in total.
    case launch(budget: TimeInterval)
    /// The read of a join: the whole folder, every listed device file, and the legacy file's
    /// settings. The host reads the folder the user chose, not yet the active one.
    case join
}

/// An opaque name of a sync folder that the host derives from the folder's bookmark.
typealias SyncFolderIdentity = String

/// What the user asks of the engine.
nonisolated enum SyncCommand: Hashable, Sendable {
    /// Apply what waits and relaunch.
    case restart
    /// Turn On…: join the folder the user chose. Nothing changes until the join commits.
    case turnOn(SyncFolderIdentity)
    /// Change…: join another folder; Cancel keeps the previous one.
    case changeFolder(SyncFolderIdentity)
    /// Turn Off: stop all folder access, keep the state.
    case turnOff
    /// Cancel while a join reads the folder or asks.
    case cancelJoin
    /// A button of the question's sheet.
    case answer(SyncAnswerRequest)
    /// The user imported a settings file: its values are in the snapshot, and they are the
    /// user's changes.
    case importFinished(SyncSnapshot)
}

/// What happened.
nonisolated enum SyncEvent: Sendable {
    /// The app starts. For this event the `state` argument of ``SyncEngine/handle(_:state:environment:)``
    /// is not used: the state comes from ``SyncLaunchInput/stored``.
    case launch(SyncLaunchInput)
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
    /// The user changed units of the macOS 27 families (plan 28-09); the defaults are never
    /// diffed for these.
    case intent(SyncIntent)
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
    /// Keep this Mac's identity in the defaults: the ID, the hash that binds it to this Mac and
    /// this account, and the earlier ID (`legacyID`) that this Mac still recognizes as its own.
    case storeIdentity(mac: SyncMacID, legacyID: String?)
    /// The join committed: the folder the user chose is the sync folder now.
    case commitFolder(SyncFolderIdentity)
    /// Sync is off: the host forgets the folder and stops all access to it.
    case forgetFolder
    /// Add these applications to `KnownApplications27` (``SyncProjection/knownApplicationsUnion(_:into:)``).
    /// It never removes an element, and it comes only at launch and at Restart.
    case applyKnownApplications([String])
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

// MARK: - Draft

/// What a step holds while the engine decides: the state, the writes to the defaults and the
/// effects, in the order the host must run them.
nonisolated struct SyncDraft {
    /// The state the step started from; a persist is due when the new state differs from it.
    let original: SyncState
    var state: SyncState
    /// The values to write to the defaults, in one `applyUnits` effect.
    var applies: [SyncUnitKey: SyncPayload] = [:]
    /// Effects that must run before anything is persisted.
    var leading: [SyncEffect] = []
    var effects: [SyncEffect] = []

    init(_ state: SyncState, original: SyncState? = nil) {
        self.original = original ?? state
        self.state = state
    }

    /// The step: leading effects, the applies, the persist when anything persistent changed,
    /// then the rest, so Sigma is persisted before any file is written.
    mutating func finish() -> SyncStep {
        var list = leading
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

// MARK: - Engine

/// The decision core of the redesigned settings sync: one entry point, pure transitions.
///
/// An event, the state and the environment go in; the new state and an ordered list of effects
/// come out. The engine does no I/O, reads no clock, uses no randomness and iterates every
/// dictionary and set sorted, so one input gives one output.
nonisolated enum SyncEngine {
    /// How long the legacy status line shows after the legacy file last changed.
    static let legacyDisplayHorizon: TimeInterval = 30 * 24 * 3600

    static func handle(_ event: SyncEvent, state: SyncState, environment: SyncEnvironment) -> SyncStep {
        if case .launch(let input) = event {
            return launch(input, environment: environment)
        }
        var draft = SyncDraft(state)
        switch event {
        case .launch:
            break
        case .defaultsChanged(let snapshot):
            let previous = draft.state.session.snapshot
            draft.state.session.snapshot = snapshot
            if state.isEnabled {
                // A change that only learned applications waits for the hour; a change of a key that does not
                // sync (a learned list, a flag, a window frame) has nothing to capture and must not postpone the
                // capture of a user's change that is waiting; anything else is captured and published as before.
                if let previous, previous.values == snapshot.values, previous.aliased == snapshot.aliased {
                    if previous.known27 != snapshot.known27 {
                        learnKnownApplications(&draft, environment: environment)
                    }
                } else {
                    draft.effects.append(.schedule(.capture, after: SyncTimer.capture.delay))
                }
            }
        case .quit(let snapshot):
            draft.state.session.snapshot = snapshot
            if state.isEnabled {
                capture(&draft, environment: environment)
                publish(&draft, trigger: .quit, environment: environment)
            }
        case .timer(let timer):
            onTimer(timer, &draft, environment: environment)
        case .folderRead(let read, let purpose):
            if case .join = purpose {
                onJoinRead(read, &draft, environment: environment)
            } else if state.isEnabled, state.pendingJoin == nil {
                // While a join waits, it owns the folder: no other read is merged.
                onRead(read, purpose: purpose, &draft, environment: environment)
            }
        case .writeFinished(let result):
            onWrite(result, &draft)
        case .command(let command):
            onCommand(command, &draft, environment: environment)
        case .intent(let intent):
            onIntent(intent, &draft, environment: environment)
        }
        return draft.finish()
    }

    // MARK: Timers

    private static func onTimer(_ timer: SyncTimer, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        if let pending = draft.state.pendingJoin {
            // A join in flight owns the folder: only its own reads run, and a change of the
            // defaults waits until the join is decided (capture is a diff, nothing is lost).
            if pending.phase == .reading, timer == .check || timer == .periodic {
                draft.effects.append(.readFolder(readRequest(.join, draft.state)))
            }
            return
        }
        guard draft.state.isEnabled else {
            return
        }
        switch timer {
        case .capture:
            capture(&draft, environment: environment)
            publish(&draft, trigger: .ownChange, environment: environment)
        case .relay:
            // A change the user made since the last capture belongs in the file that goes out now.
            capture(&draft, environment: environment)
            publish(&draft, trigger: .relay, environment: environment)
        case .healing:
            capture(&draft, environment: environment)
            publish(&draft, trigger: .healing, environment: environment)
        case .check:
            draft.effects.append(.readFolder(readRequest(.check, draft.state)))
        case .periodic:
            draft.effects.append(.readFolder(readRequest(.check, draft.state)))
            draft.effects.append(.schedule(.periodic, after: SyncTimer.periodic.delay))
        case .learned:
            draft.state.session.isLearnedTimerPending = false
            capture(&draft, environment: environment)
            publish(&draft, trigger: .learned, environment: environment)
        }
    }

    static func readRequest(_ purpose: SyncReadPurpose, _ state: SyncState) -> SyncReadRequest {
        // The legacy file's settings are read only to found a group, at a join; afterwards
        // only its metadata, for the status line.
        let legacy: SyncLegacyRequest
        if case .join = purpose {
            legacy = .settings
        } else {
            legacy = state.legacy.foundingDigest == nil ? .none : .metadata
        }
        var macs = Set(state.replica.context.macs)
        macs.formUnion(state.previousMacIDs)
        macs.insert(state.mac)
        return SyncReadRequest(purpose: purpose, legacy: legacy, knownMacs: macs.sorted())
    }

    // MARK: Capture and publish

    static func capture(_ draft: inout SyncDraft, environment: SyncEnvironment) {
        // A join that waits decides against the state as it is: nothing is minted meanwhile, and what the
        // user changes is captured once the join is decided.
        guard let snapshot = draft.state.session.snapshot, draft.state.pendingJoin == nil else {
            return
        }
        drainIntents(&draft, environment: environment)
        draft.state = SyncCapture.capture(snapshot, state: draft.state, environment: environment)
        learnKnownApplications(&draft, environment: environment)
    }

    /// Asks the publish rules and, when they say write, emits the write.
    static func publish(_ draft: inout SyncDraft, trigger: SyncWriteTrigger, environment: SyncEnvironment) {
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

    private static func onWrite(_ result: SyncWriteResult, _ draft: inout SyncDraft) {
        draft.state = SyncPublish.apply(result, to: draft.state)
        if case .failed(.ownFileChanged) = result {
            // The own file is not what this session read: read it again before any write.
            draft.effects.append(.schedule(.check, after: SyncTimer.check.delay))
        }
    }

    // MARK: Reads

    private static func onRead(_ read: SyncFolderRead, purpose: SyncReadPurpose, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        // A change made while the folder was away still counts: capture first, then merge.
        capture(&draft, environment: environment)
        let merged = SyncMerge.merge(read, into: draft.state, environment: environment)
        draft.state = merged.state
        if merged.reidentified {
            draft.leading.append(.storeIdentity(mac: draft.state.mac, legacyID: nil))
        }
        // A state that was behind the defaults mints nothing until the own file was joined.
        if resolveDeferredCapture(&draft.state) {
            capture(&draft, environment: environment)
        }
        if let snapshot = draft.state.session.snapshot {
            let plan = SyncPlan.plan(state: draft.state, snapshot: snapshot, environment: environment)
            draft.state = SyncCapture.settle(plan, snapshot: snapshot, state: draft.state, environment: environment)
            if case .launch = purpose {
                // The launch applies what arrived in time, as it applies what waited; a later
                // check only shows the Restart hint.
                let changes = plan.fastForwardPayloads
                if !changes.isEmpty {
                    draft.applies = changes
                    draft.state = SyncCapture.applied(changes, snapshot: snapshot, state: draft.state, environment: environment)
                }
            }
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

    /// Lets capture run once the own file was read and joined, when the state was behind.
    ///
    /// - Returns: Whether capture was deferred until now.
    static func resolveDeferredCapture(_ state: inout SyncState) -> Bool {
        guard state.captureDeferred, state.session.ownFile != .unread else {
            return false
        }
        state.captureDeferred = false
        state.session.isTrusted = true
        return true
    }

    // MARK: Commands

    private static func onCommand(_ command: SyncCommand, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        switch command {
        case .restart:
            guard draft.state.isEnabled else {
                return
            }
            restart(&draft, environment: environment)
        case .turnOn(let folder):
            startJoin(folder, isChange: false, &draft, environment: environment)
        case .changeFolder(let folder):
            startJoin(folder, isChange: draft.state.isEnabled, &draft, environment: environment)
        case .turnOff:
            turnOff(&draft)
        case .cancelJoin:
            cancelJoin(&draft)
        case .answer(let request):
            answer(request, &draft, environment: environment)
        case .importFinished(let snapshot):
            draft.state.session.snapshot = snapshot
            guard draft.state.isEnabled, draft.state.pendingJoin == nil else {
                return
            }
            // An import is the user's change: capture it now and publish it.
            capture(&draft, environment: environment)
            publish(&draft, trigger: .ownChange, environment: environment)
        }
    }

    /// Turn Off: all folder access stops, the state and its open siblings stay, the hint and
    /// the timers go.
    private static func turnOff(_ draft: inout SyncDraft) {
        guard draft.state.isEnabled || draft.state.pendingJoin != nil else {
            return
        }
        draft.state.isEnabled = false
        draft.state.pendingJoin = nil
        draft.state.session.waitingFiles = 0
        for timer in [SyncTimer.capture, .relay, .check, .periodic, .healing] {
            draft.effects.append(.cancelTimer(timer))
        }
        draft.effects.append(.forgetFolder)
    }

    // MARK: Restart

    private static func restart(_ draft: inout SyncDraft, environment: SyncEnvironment) {
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
        applyKnownApplications(&draft, environment: environment)
        publish(&draft, trigger: .ownChange, environment: environment)
        draft.effects.append(.relaunch)
    }

    // MARK: View

    /// What the app shows of `state`: the hint and the status lines, computed from the
    /// persisted replica, the last snapshot and the session.
    static func view(of state: SyncState, environment: SyncEnvironment) -> SyncView {
        // Turned off: no hint, no line; the state is kept but says nothing.
        guard state.isEnabled || state.pendingJoin != nil else {
            return SyncView(hint: nil, lines: [])
        }
        let plan = state.session.snapshot.map { SyncPlan.plan(state: state, snapshot: $0, environment: environment) }
        var lines: [SyncStatusLine] = []
        if let pending = state.pendingJoin {
            if pending.phase == .reading {
                lines.append(.joining(waitingFiles: state.session.waitingFiles))
            }
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
        var hint: SyncHint?
        if let pending = state.pendingJoin {
            hint = pending.phase == .asking ? .chooseAfterJoin : nil
        } else {
            hint = plan?.hint
            // Later hides the question until the next launch; a Restart hint stays.
            if hint == .choose, let plan, state.laterLaunch == state.launchCount {
                hint = plan.fastForwards.isEmpty ? nil : .restart
            }
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
