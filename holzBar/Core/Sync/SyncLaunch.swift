//
//  SyncLaunch.swift
//  holzBar
//

import Foundation

/// What the host reads of this Mac's identity before the engine starts (analysis section 4.5).
nonisolated struct SyncIdentityInput: Sendable {
    /// `SettingsSyncDeviceID`.
    var storedID: String?
    /// `SettingsSyncDeviceHash`, the salted hash that binds the ID to this Mac and account.
    var storedHash: String?
    /// `SettingsSyncDeviceSalt`.
    var salt: Data?
    /// The hardware UUID, if it can be read. It is only hashed and never stored.
    var hardwareID: String?
    /// The user ID of the running account.
    var uid: UInt32

    init(storedID: String? = nil, storedHash: String? = nil, salt: Data? = nil, hardwareID: String? = nil, uid: UInt32 = 0) {
        self.storedID = storedID
        self.storedHash = storedHash
        self.salt = salt
        self.hardwareID = hardwareID
        self.uid = uid
    }
}

/// Everything the engine needs to start: the local settings, what Sigma held on disk, the
/// identity inputs and the defaults the trust checks compare with Sigma.
nonisolated struct SyncLaunchInput: Sendable {
    var snapshot: SyncSnapshot
    /// What reading Sigma gave.
    var stored: SyncStateDecodeResult
    var identity: SyncIdentityInput
    /// `SettingsSyncGeneration`, `nil` if the defaults hold none.
    var defaultsGeneration: UInt64?
    /// `SettingsSyncLastSynced`, the tripwire that 0.0.7-beta1 writes at every push and apply.
    var lastSyncedSeen: Date?
    /// Whether the user has sync turned on.
    var syncIsOn: Bool
    /// The folder the user chose, if sync is on or a join is pending.
    var folder: SyncFolderIdentity?

    init(
        snapshot: SyncSnapshot = SyncSnapshot(),
        stored: SyncStateDecodeResult = .unreadable,
        identity: SyncIdentityInput = SyncIdentityInput(),
        defaultsGeneration: UInt64? = nil,
        lastSyncedSeen: Date? = nil,
        syncIsOn: Bool = false,
        folder: SyncFolderIdentity? = nil
    ) {
        self.snapshot = snapshot
        self.stored = stored
        self.identity = identity
        self.defaultsGeneration = defaultsGeneration
        self.lastSyncedSeen = lastSyncedSeen
        self.syncIsOn = syncIsOn
        self.folder = folder
    }
}

/// What the launch found out about Sigma (analysis section 4.6.6, step 4). Sigma is trusted for
/// capture only if all three checks hold; otherwise this Mac joins without capturing and mints
/// nothing.
nonisolated struct SyncTrust: Hashable, Sendable {
    /// How `SettingsSyncGeneration` compares with Sigma's generation.
    enum Generation: Hashable, Sendable {
        /// Equal: Sigma is the state of the last persist.
        case matches
        /// The defaults are lower: the preferences were rolled back (a restore of the
        /// preferences, or a reinstall).
        case rolledBack
        /// The defaults are higher: Sigma is behind (a crash, or Sigma restored alone).
        case behind
    }

    /// What capture may do.
    enum Mode: Hashable, Sendable {
        /// Capture runs at once.
        case trusted
        /// Capture waits until the own file was read and joined.
        case deferred
        /// Sigma is no evidence of anything: this Mac joins without capturing.
        case untrusted
    }

    /// Whether a valid Sigma was loaded at all.
    var hasState = false
    var generation = Generation.matches
    /// Whether `SettingsSyncLastSynced` is what Sigma last saw. A change means a build before
    /// the redesign synced on this Mac.
    var tripwireMatches = true
    /// Whether the identity changed while the settings differ from what Sigma last captured.
    var identityChangedWithDifferences = false

    var mode: Mode {
        guard hasState, tripwireMatches, !identityChangedWithDifferences else {
            return .untrusted
        }
        switch generation {
        case .matches:
            return .trusted
        case .behind:
            return .deferred
        case .rolledBack:
            return .untrusted
        }
    }
}

nonisolated extension SyncState {
    /// Whether this state holds a group's history: it was founded or joined once.
    var hasGroup: Bool {
        !replica.context.isEmpty || !baseline.isEmpty
    }
}

/// The launch of the engine (analysis section 4.6.6): the identity check, the trust checks,
/// capture for a trusted state, the application of every waiting fast-forward and the bounded
/// read of the folder. The launch writes no file.
nonisolated extension SyncEngine {
    /// The identity zero, used only to keep the compiler honest where a fresh identity is missing.
    private static let placeholderID = SyncMacID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))

    /// What the identity check made of this launch.
    private struct LaunchIdentity {
        var state: SyncState
        /// Sigma as read, before any identity change.
        var stored: SyncState?
        /// Whether the state's identity differs from the one Sigma was written under.
        var changed: Bool
        var effects: [SyncEffect]
    }

    static func launch(_ input: SyncLaunchInput, environment: SyncEnvironment) -> SyncStep {
        guard let identity = resolveIdentity(input, environment: environment) else {
            // Without a fresh identity there is nothing to build a state from: stay inert.
            return SyncStep(state: SyncState(mac: placeholderID, nonce: "", isEnabled: false), effects: [])
        }
        var state = identity.state
        let defaultsGeneration = input.defaultsGeneration ?? 0
        // An upgrade from macOS 26 to 27 is recognised here, before anything is decided with the state.
        SyncLayout27.noteSystemGeneration(&state, snapshot: input.snapshot, environment: environment)

        var trust = SyncTrust()
        if let stored = identity.stored {
            trust.hasState = true
            if defaultsGeneration == stored.generation {
                trust.generation = .matches
            } else {
                trust.generation = defaultsGeneration < stored.generation ? .rolledBack : .behind
            }
            trust.tripwireMatches = input.lastSyncedSeen == stored.legacy.lastSyncedSeen
            trust.identityChangedWithDifferences = identity.changed
                && differsFromBaseline(input.snapshot, state: state, table: environment.table)
        }

        // The guard exists so the simulator can run an engine that trusts every state it loads: a
        // state that is no evidence then mints at launch (analysis section 5.6).
        let mode: SyncTrust.Mode = environment.guards.contains(.trustedState) ? trust.mode : (trust.hasState ? .trusted : .untrusted)
        // The counter never goes below what the mirror in the defaults and the high-water mark in the Caches say this installation
        // minted: a Sigma that was restored alone is behind them, and persisting it as it is would lower the mirror.
        state.counter = max(state.counter, environment.counterFloors.mirror, environment.counterFloors.highWater)
        state.session = SyncSession()
        state.session.snapshot = input.snapshot
        state.session.trust = trust
        state.session.lastSyncedSeen = input.lastSyncedSeen
        state.isEnabled = input.syncIsOn
        if trust.hasState, mode == .deferred {
            state.captureDeferred = true
        }
        if mode == .untrusted {
            state.captureDeferred = false
        }
        state.session.isTrusted = mode == .trusted && !state.captureDeferred
        if let pending = state.pendingJoin {
            // The trust checks passed because the join began and persisted; what the state was worth then is
            // what it is worth until the join is decided, unless the preferences were rolled back since: a state
            // that no longer matches its defaults is no evidence, and committing it as the group's would publish
            // the rolled-back settings as deletions.
            state.session.isTrusted = pending.wasTrusted && mode != .untrusted
        }

        // Sigma is persisted above the defaults, so a state that was behind catches up.
        var original = identity.stored ?? state
        original.generation = max(original.generation, defaultsGeneration)
        var draft = SyncDraft(state, original: original)
        draft.leading = identity.effects
        if input.syncIsOn {
            draft.state.launchCount += 1
        }

        if var pending = draft.state.pendingJoin {
            if pending.phase == .asking, pending.wasTrusted, mode == .untrusted {
                // The question was built from a state that was evidence then. The preferences were rolled back or the state was
                // copied since, so the rows (and the commit that follows them) would treat the difference as the user's changes: the
                // join reads the folder again and asks about what the state is worth now.
                pending = SyncPendingJoin(
                    replica: .empty,
                    shown: [:],
                    isFounding: false,
                    folderIdentity: pending.folderIdentity,
                    phase: .reading,
                    isChange: pending.isChange
                )
                draft.state.pendingJoin = pending
            }
            if mode == .untrusted, var current = draft.state.pendingJoin {
                // Preferences that were rolled back (or copied) while the join waited are not a change of the user's: what the settings
                // hold now is the start of the join, not what they held before.
                current.localAtDecision = SyncJoin.localDigests(snapshot: input.snapshot, replica: .empty, legacy: nil, environment: environment)
                draft.state.pendingJoin = current
            }
            // A join that was waiting at quit goes on: the same rows come back.
            if input.syncIsOn {
                capture(&draft, environment: environment)
            }
            if pending.phase == .reading {
                draft.effects.append(.readFolder(readRequest(.join, draft.state)))
            }
            resolveAskingJoin(&draft, environment: environment)
            return draft.finish()
        }
        guard input.syncIsOn else {
            if mode == .untrusted, trust.hasState {
                // A state that is no evidence stays no evidence. This launch persists it with the identity and the generation it just
                // settled on, and the next launch compares the defaults with that and trusts it: its baselines would then make the
                // settings that a reinstall or a restore took away look like deletions by the user, and turning sync on would
                // publish them (found by INV-A6 seed 77). What a join with dot-less values forgets is forgotten now; the replica
                // stays, so the join into the group still knows its own entries and takes the group's values where the settings
                // hold none.
                draft.state.applied = [:]
                draft.state.baseline = [:]
                draft.state.localOnly = [:]
                draft.state.localOrigin = [:]
            }
            // Off: the state is kept, nothing else happens.
            return draft.finish()
        }
        if mode == .untrusted || identity.changed {
            // Joining: the folder is read whole, nothing is captured, nothing is minted, and
            // nothing from the folder is applied in this launch.
            guard let folder = input.folder else {
                return draft.finish()
            }
            startJoin(folder, isChange: false, &draft, environment: environment)
            return draft.finish()
        }

        // Trusted, or waiting for the own file.
        capture(&draft, environment: environment)
        if !draft.state.captureDeferred, let snapshot = draft.state.session.snapshot {
            // Every valid fast-forward applies, from the persisted replica alone: the folder
            // may be unreachable (INV-9).
            let plan = SyncPlan.plan(state: draft.state, snapshot: snapshot, environment: environment)
            draft.state = SyncCapture.settle(plan, snapshot: snapshot, state: draft.state, environment: environment)
            let changes = plan.fastForwardPayloads
            if !changes.isEmpty {
                draft.applies = changes
                draft.state = SyncCapture.applied(changes, snapshot: snapshot, state: draft.state, environment: environment)
            }
            applyKnownApplications(&draft, environment: environment)
        }
        draft.effects.append(.readFolder(readRequest(.launch(budget: launchReadBudget), draft.state)))
        draft.effects.append(.schedule(.periodic, after: SyncTimer.periodic.delay))
        return draft.finish()
    }

    /// The most the launch waits for the folder, in seconds (analysis section 4.6.6, step 6).
    static let launchReadBudget: TimeInterval = 1

    // MARK: Identity

    /// Decides the identity and builds the state to start from: Sigma re-identified when the
    /// identity changed, or a new state.
    private static func resolveIdentity(_ input: SyncLaunchInput, environment: SyncEnvironment) -> LaunchIdentity? {
        let fresh = environment.freshIdentity
        var needsFresh = false
        let decision = SyncIdentity.check(
            storedID: input.identity.storedID,
            storedHash: input.identity.storedHash,
            salt: input.identity.salt,
            hardwareID: input.identity.hardwareID,
            uid: input.identity.uid,
            makeID: {
                guard let fresh else {
                    needsFresh = true
                    return placeholderID
                }
                return fresh.mac
            }
        )
        var mac: SyncMacID
        var legacyID: String?
        var store = false
        switch decision {
        case .same(let id):
            mac = id
        case .rotated(let new, let legacy):
            mac = new
            legacyID = legacy
            store = true
        case .firstRun(let id):
            mac = id
            store = true
        case .noHardwareID(let id):
            if let id {
                mac = id
            } else {
                // No identity can be kept: make one.
                guard let fresh else {
                    return nil
                }
                mac = fresh.mac
                store = true
            }
        }
        if needsFresh {
            return nil
        }
        var effects: [SyncEffect] = []
        var changed = false
        var state: SyncState
        var stored: SyncState?
        if case .state(var existing) = input.stored {
            stored = existing
            if existing.mac == mac {
                // The same identity.
            } else if case .same = decision, existing.previousMacIDs.contains(mac) {
                // The engine re-identified after the defaults were last written: Sigma's
                // identity is the newer one, and the defaults catch up.
                mac = existing.mac
                store = false
                effects.append(.storeIdentity(mac: existing.mac, legacyID: nil))
            } else {
                // A copy of another Mac's state, or the defaults lost: Sigma stays a valid
                // causal state under a new identity.
                existing = SyncIdentity.reidentified(existing, newMac: mac, newNonce: fresh?.nonce ?? existing.nonce, suspect: [], floors: environment.counterFloors)
                changed = true
            }
            state = existing
        } else {
            guard let fresh else {
                return nil
            }
            state = SyncState(mac: mac, nonce: fresh.nonce, isEnabled: false)
        }
        if store {
            effects.append(.storeIdentity(mac: mac, legacyID: legacyID))
            // The earlier ID is what this Mac's writes of the legacy file carry.
            if let legacyID, state.legacy.legacyDeviceID == nil {
                state.legacy.legacyDeviceID = legacyID
            }
        }
        return LaunchIdentity(state: state, stored: stored, changed: changed, effects: effects)
    }

    /// Whether the local settings differ from what Sigma last captured: some unit has another
    /// value than its baseline, or a unit with no baseline holds a value.
    private static func differsFromBaseline(_ snapshot: SyncSnapshot, state: SyncState, table: SyncUnitTable) -> Bool {
        for (key, baseline) in state.baseline.sorted(by: { $0.key < $1.key }) where !SyncLayout27.isIntentCaptured(key) {
            let local = SyncProjection.localValue(key, in: snapshot.values, table: table)?.digest ?? .unset
            if local != baseline {
                return true
            }
        }
        for key in snapshot.values.keys.sorted() where state.baseline[key] == nil && !SyncLayout27.isIntentCaptured(key) {
            // A whole unit that holds a value Sigma never captured is a difference; an item of
            // a family without a baseline had no value when Sigma was made.
            if let descriptor = table.descriptor(for: key), !descriptor.isFamily, !descriptor.isSet {
                return true
            }
        }
        return false
    }
}
