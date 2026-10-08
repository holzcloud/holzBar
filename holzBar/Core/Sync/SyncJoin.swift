//
//  SyncJoin.swift
//  holzBar
//

import Foundation

/// What a join makes of one unit (analysis section 4.6.8, step 4), or of the whole join.
///
/// "No user value" means the key is absent from the defaults, never "equal to its default"
/// (decision D-10), so a key that holds the default value is a value, and a fresh install
/// adopts the folder without a question.
nonisolated enum SyncJoinPreview: Hashable, Sendable {
    /// This Mac's value equals the folder's single value: adopt its dots, silently. A value
    /// from the legacy file becomes this Mac's entry.
    case adopt
    /// This Mac has no value and the folder has one: it waits as a fast-forward after the commit.
    case fastForward
    /// This Mac has a value and the folder has none: published as this Mac's entry, no question.
    case publish
    /// This Mac's value differs from the folder's single value: a row.
    case row
    /// This Mac's value equals one of several: adopt that sibling's dots, and take part in an
    /// ordinary conflict after the commit.
    case adoptSibling
    /// This Mac's value equals none of several: a row that lists every value, with a pop-up.
    case multiRow
    /// This Mac has no value and the folder has several: a conflict between other Macs after
    /// the commit, with no hint and neither value applied.
    case bystander
    /// Neither side has a value.
    case nothing
    /// Files are still being read or downloaded, so nothing can be decided.
    case waiting(files: Int)
    /// The folder cannot be used, so the join cannot go on.
    case refused
}

/// The join: Turn On…, Change…, a first run and a state that is not trusted (analysis section
/// 4.6.8). Nothing is published or applied from the folder before the commit (INV-J1), and the
/// pending join survives a relaunch.
nonisolated enum SyncJoin {
    /// What a join makes of one unit.
    ///
    /// - Parameters:
    ///   - key: The unit.
    ///   - local: This Mac's value, `nil` when the key is absent.
    ///   - folder: The distinct values the folder holds for the unit.
    ///   - legacy: The legacy file's value, used only when the folder holds none (founding).
    ///   - hasValue: Whether this Mac has a value of its own to protect. It is `local != nil` unless
    ///     the value is the visible section an absent `l27` entry reads as, or one holzBar placed
    ///     itself after an upgrade to macOS 27 (``SyncLayout27/noteSystemGeneration(_:snapshot:environment:)``).
    static func preview(
        unit key: SyncUnitKey,
        local: SyncValue?,
        folder: [SyncPayload],
        legacy: SyncValue?,
        hasValue: Bool? = nil,
        environment: SyncEnvironment
    ) -> SyncJoinPreview {
        let hasValue = hasValue ?? (local != nil)
        let values: [SyncPayload] = folder.isEmpty ? (legacy.map { [.value($0)] } ?? []) : folder
        guard !values.isEmpty else {
            return hasValue ? .publish : .nothing
        }
        let isEqual = values.contains { SyncCapture.matches($0, local: local, key: key, table: environment.table) }
        if values.count == 1 {
            if isEqual {
                return .adopt
            }
            return hasValue ? .row : .fastForward
        }
        if isEqual {
            return .adoptSibling
        }
        return hasValue ? .multiRow : .bystander
    }

    /// Whether this Mac holds a value of `key` that is its own: a value in the defaults, and for
    /// the macOS 27 families one that holzBar did not place itself (an absent `l27` entry is the
    /// visible section, which is no value to protect, D-04).
    static func hasOwnValue(_ key: SyncUnitKey, snapshot: SyncSnapshot, origins: [SyncUnitKey: SyncLocalOrigin]) -> Bool {
        guard SyncLayout27.isIntentCaptured(key) else {
            return snapshot.values[key] != nil
        }
        return snapshot.values[key] != nil && origins[key] != .automatic
    }

    /// The overall state of a read: the join waits while files are not read, and cannot go on
    /// when the folder cannot be used.
    static func overall(of read: SyncFolderRead, waiting: Int) -> SyncJoinPreview? {
        guard read.availability == .available else {
            return .refused
        }
        return waiting > 0 ? .waiting(files: waiting) : nil
    }

    // MARK: Units

    /// The units a join looks at: the replica's, this Mac's and the legacy file's that this
    /// build authors here and does not map to another key.
    static func candidateKeys(replica: SyncReplica, snapshot: SyncSnapshot, legacy: SyncPendingLegacy?, environment: SyncEnvironment) -> [SyncUnitKey] {
        var keys = Set(replica.registers.keys)
        keys.formUnion(snapshot.values.keys)
        if let legacy {
            keys.formUnion(legacy.units.keys)
        }
        let table = environment.table
        return keys.sorted().filter { key in
            guard let descriptor = table.descriptor(for: key), !descriptor.isSet else {
                return false
            }
            return table.isApplicableHere(key, generation: environment.generation) && !snapshot.aliased.contains(key)
        }
    }

    /// Why this Mac's value cannot be published, if it cannot.
    static func localOnlyReason(_ local: SyncValue?, key: SyncUnitKey, table: SyncUnitTable) -> SyncLocalOnlyReason? {
        guard let local, let descriptor = table.descriptor(for: key) else {
            return nil
        }
        if local == SyncProjection.unrepresentable || !descriptor.validate(key.itemName, local) {
            return .invalid
        }
        return descriptor.isOverCap(local) ? .oversize : nil
    }

    /// Whether this build can use the folder's value of `key`.
    static func isUsable(_ payload: SyncPayload, key: SyncUnitKey, table: SyncUnitTable) -> Bool {
        guard case .value(let value) = payload, let descriptor = table.descriptor(for: key) else {
            return true
        }
        return descriptor.validate(key.itemName, value) && !descriptor.isOverCap(value)
    }

    /// The legacy file's units this build can use, from its settings.
    static func usableLegacyUnits(_ settings: [String: SyncValue], environment: SyncEnvironment) -> [SyncUnitKey: SyncValue] {
        var units: [SyncUnitKey: SyncValue] = [:]
        let table = environment.table
        for (key, value) in SyncProjection.units(fromLegacySettings: settings, table: table) {
            guard
                let descriptor = table.descriptor(for: key), !descriptor.isSet,
                table.isAuthoredHere(key, generation: environment.generation),
                value != SyncProjection.unrepresentable,
                descriptor.validate(key.itemName, value), !descriptor.isOverCap(value)
            else {
                continue
            }
            units[key] = value
        }
        return units
    }

    // MARK: Rows

    /// The question of a join: the units that need an answer, and the dots shown for each.
    /// `restrictedTo` keeps the rows of a question that was shown already.
    static func question(pending: SyncPendingJoin, state: SyncState, restrictedTo: Set<SyncUnitKey>?, environment: SyncEnvironment) -> SyncQuestion? {
        var tentative = state
        tentative.replica = pending.replica
        let snapshot = state.session.snapshot ?? SyncSnapshot()
        var rows: [SyncRow]
        if pending.isSameGroup {
            // Capture ran first, so the rows are the units changed on both sides.
            let plan = SyncPlan.plan(state: tentative, snapshot: snapshot, environment: environment)
            rows = SyncRows.running(state: tentative, plan: plan, snapshot: snapshot, environment: environment)
        } else {
            rows = dotlessRows(replica: pending.replica, snapshot: snapshot, legacy: pending.legacy, origins: state.localOrigin, environment: environment)
        }
        if let restrictedTo {
            rows = rows.filter { restrictedTo.contains($0.unit) }
        }
        guard !rows.isEmpty else {
            return nil
        }
        let shown = restrictedTo == nil ? SyncRows.shown(rows, in: pending.replica) : pending.shown
        return SyncQuestion(kind: .joining, rows: rows, shown: shown)
    }

    /// The rows of a join with dot-less local values: the previews that ask, and the hotkeys
    /// that would share a key combination if the folder's value applied.
    private static func dotlessRows(
        replica: SyncReplica,
        snapshot: SyncSnapshot,
        legacy: SyncPendingLegacy?,
        origins: [SyncUnitKey: SyncLocalOrigin],
        environment: SyncEnvironment
    ) -> [SyncRow] {
        let table = environment.table
        var rows: [SyncRow] = []
        var incoming: [SyncUnitKey: SyncPayload] = [:]
        func folderValues(_ key: SyncUnitKey) -> [SyncRowValue] {
            let live = replica.live(key)
            if !live.isEmpty {
                return SyncRows.values(of: live)
            }
            guard let value = legacy?.units[key] else {
                return []
            }
            return [SyncRowValue(value: .value(value), at: legacy?.modified ?? environment.now, source: .legacyFile)]
        }
        for key in candidateKeys(replica: replica, snapshot: snapshot, legacy: legacy, environment: environment) {
            let local = SyncProjection.localValue(key, in: snapshot.values, table: table)
            let folder = replica.distinctValues(key)
            guard localOnlyReason(local, key: key, table: table) == nil, folder.allSatisfy({ isUsable($0, key: key, table: table) }) else {
                continue
            }
            let hasValue = hasOwnValue(key, snapshot: snapshot, origins: origins)
            switch preview(unit: key, local: local, folder: folder, legacy: legacy?.units[key], hasValue: hasValue, environment: environment) {
            case .row:
                rows.append(SyncRow(unit: key, local: SyncRows.local(key, snapshot: snapshot, environment: environment), folder: folderValues(key), style: .twoWay))
            case .multiRow:
                rows.append(SyncRow(unit: key, local: SyncRows.local(key, snapshot: snapshot, environment: environment), folder: folderValues(key), style: .multi))
            case .fastForward:
                incoming[key] = folder.first ?? legacy?.units[key].map { .value($0) }
            default:
                break
            }
        }
        for clash in SyncPlan.clashes(fastForwards: incoming, snapshot: snapshot) {
            for unit in clash.units where incoming[unit] != nil {
                guard let partner = clash.units.first(where: { $0 != unit }) else {
                    continue
                }
                rows.append(SyncRow(unit: unit, local: nil, folder: folderValues(unit), style: .clash(partner: partner)))
            }
        }
        return rows.sorted { $0.unit < $1.unit }
    }

    // MARK: Commit

    /// The state of this Mac's units once it commits to a folder whose group it was not in: its
    /// values are dot-less, so nothing of Sigma's old bookkeeping is evidence. `skipping` holds
    /// the units a question decides.
    static func settleDotless(
        _ state: inout SyncState,
        snapshot: SyncSnapshot,
        legacy: SyncPendingLegacy?,
        skipping: Set<SyncUnitKey>,
        environment: SyncEnvironment
    ) {
        let table = environment.table
        // What holzBar placed itself after an upgrade is no value of the user's (INV-L6); the rest of
        // the old bookkeeping is no evidence of anything.
        let origins = state.localOrigin
        state.applied = [:]
        state.baseline = [:]
        state.localOnly = [:]
        state.localOrigin = [:]
        // A whole unit that holds no value has the baseline "unset", so a value the user sets
        // later is captured as a change.
        for key in table.wholeUnitKeys where table.isAuthoredHere(key, generation: environment.generation) {
            state.baseline[key] = SyncProjection.localValue(key, in: snapshot.values, table: table)?.digest ?? .unset
        }
        for key in candidateKeys(replica: state.replica, snapshot: snapshot, legacy: legacy, environment: environment) {
            let local = SyncProjection.localValue(key, in: snapshot.values, table: table)
            state.baseline[key] = local?.digest ?? .unset
            if let reason = localOnlyReason(local, key: key, table: table) {
                state.localOnly[key] = reason
                continue
            }
            if skipping.contains(key) {
                state.localOrigin[key] = .preexisting
                continue
            }
            let hasValue = hasOwnValue(key, snapshot: snapshot, origins: origins)
            if SyncLayout27.isIntentCaptured(key), origins[key] == .automatic, snapshot.values[key] != nil {
                state.localOrigin[key] = .automatic
            }
            let live = state.replica.live(key)
            let folder = state.replica.distinctValues(key)
            guard folder.allSatisfy({ isUsable($0, key: key, table: table) }) else {
                continue
            }
            let legacyValue = legacy?.units[key]
            switch preview(unit: key, local: local, folder: folder, legacy: legacyValue, hasValue: hasValue, environment: environment) {
            case .adopt, .adoptSibling:
                if live.isEmpty {
                    // A value of the legacy file becomes this Mac's entry.
                    if let local, hasValue {
                        SyncCapture.mint(key, payload: .value(local), digest: local.digest, state: &state, environment: environment)
                    }
                } else {
                    state.applied[key] = live.filter { SyncCapture.matches($0.payload, local: local, key: key, table: table) }.map(\.dot)
                }
            case .publish:
                if let local {
                    SyncCapture.mint(key, payload: .value(local), digest: local.digest, state: &state, environment: environment)
                }
            case .fastForward:
                if live.isEmpty, let legacyValue {
                    // The legacy value waits as a fast-forward: this Mac's entry carries it.
                    SyncCapture.mint(key, payload: .value(legacyValue), digest: legacyValue.digest, state: &state, environment: environment)
                    state.applied[key] = nil
                    state.baseline[key] = .unset
                }
            case .row, .multiRow:
                state.localOrigin[key] = .preexisting
            case .bystander, .nothing, .waiting, .refused:
                break
            }
        }
        if !environment.guards.contains(.absentMeansNoValue) {
            // Control engine: absence counts as a value, so a unit nobody has set is published as
            // deleted, and a Mac that never had a setting deletes it for everyone (decision D-10).
            for key in table.wholeUnitKeys where table.isAuthoredHere(key, generation: environment.generation) && !skipping.contains(key) {
                guard SyncProjection.localValue(key, in: snapshot.values, table: table) == nil, state.replica.live(key).isEmpty else {
                    continue
                }
                SyncCapture.mint(key, payload: .deleted, digest: .unset, state: &state, environment: environment)
            }
        }
    }
}

// MARK: - Engine

nonisolated extension SyncEngine {
    /// Turn On… and Change…: the folder is read whole, and nothing changes until the join
    /// commits. Capture runs once first when this Mac's state is trusted, so only units
    /// changed on both sides are asked about.
    static func startJoin(_ folder: SyncFolderIdentity, isChange: Bool, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        draft.state.session.waitingFiles = 0
        noteUpgrade(&draft, environment: environment)
        // Capture runs once, before the join: while it waits nothing is minted, because what it reads and
        // shows is decided against the state as it is now.
        capture(&draft, environment: environment)
        var pending = SyncPendingJoin(
            replica: .empty,
            shown: [:],
            isFounding: false,
            folderIdentity: folder,
            phase: .reading,
            isChange: isChange
        )
        pending.wasTrusted = draft.state.session.isTrusted
        draft.state.pendingJoin = pending
        draft.effects.append(.readFolder(readRequest(.join, draft.state)))
    }

    /// A join after an upgrade from macOS 26 to 27 treats what holzBar copied or seeded as no value of
    /// the user's. The launch records the generation first; this covers a join that comes without one.
    private static func noteUpgrade(_ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard draft.state.systemGeneration != environment.generation else {
            return
        }
        SyncLayout27.noteSystemGeneration(&draft.state, snapshot: draft.state.session.snapshot ?? SyncSnapshot(), environment: environment)
    }

    /// Cancel: the tentative state is discarded and nothing is written. After Turn On… sync
    /// stays off, and after Change… the previous folder and its state stay.
    static func cancelJoin(_ draft: inout SyncDraft) {
        guard draft.state.pendingJoin != nil else {
            return
        }
        draft.state.pendingJoin = nil
        draft.state.session.waitingFiles = 0
    }

    /// A read of a join (analysis section 4.6.8): the join waits while files are not read,
    /// then it either commits or asks.
    static func onJoinRead(_ read: SyncFolderRead, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard let pending = draft.state.pendingJoin, pending.phase == .reading else {
            return
        }
        draft.state.session.availability = read.availability
        noteUpgrade(&draft, environment: environment)
        if case .refused? = SyncJoin.overall(of: read, waiting: 0) {
            // Not found or not usable: the join goes on at the next trigger, or the user cancels.
            draft.state.session.waitingFiles = 0
            return
        }
        let snapshot = draft.state.session.snapshot ?? SyncSnapshot()
        let state = draft.state
        let isFounding = read.files.isEmpty
        let knowsFolder = read.files.contains { file in
            file.macID.map { state.replica.context[$0] > 0 || state.isOwn($0) } ?? false
        }
        // The same group: this Mac's state is trusted, and the folder is empty (the group
        // moves with the user) or holds a Mac this state knows.
        let isSameGroup = state.session.isTrusted && state.hasGroup && (knowsFolder || isFounding)

        var tentative = state
        if !isSameGroup {
            // Another group, or a state that is no evidence: this Mac's values are dot-less.
            tentative.replica = .empty
            tentative.applied = [:]
            tentative.baseline = [:]
            tentative.localOnly = [:]
            tentative.localOrigin = [:]
        }
        let merged = SyncMerge.merge(read, into: tentative, environment: environment)
        let unreadable = merged.state.refusals.values.filter { $0.reason == SyncRefusal.unreadable.code }.count
        let waiting = merged.state.session.waitingFiles + unreadable
        if case .waiting? = SyncJoin.overall(of: read, waiting: waiting) {
            draft.state.session.waitingFiles = waiting
            if !merged.downloads.isEmpty {
                draft.effects.append(.requestDownload(macs: merged.downloads))
            }
            draft.effects.append(.schedule(.check, after: SyncTimer.check.delay))
            return
        }

        // Adopt what is not tentative: the identity the merge settled on, the refusals, the
        // counters and the session. The replica and the unit bookkeeping wait for the commit.
        var adopted = merged.state
        adopted.replica = state.replica
        if !isSameGroup {
            adopted.applied = state.applied
            adopted.baseline = state.baseline
            adopted.localOnly = state.localOnly
            adopted.localOrigin = state.localOrigin
        }
        if merged.reidentified {
            draft.leading.append(.storeIdentity(mac: adopted.mac, legacyID: nil))
        }
        draft.state = adopted

        var proposed = pending
        proposed.replica = merged.state.replica
        proposed.isFounding = isFounding
        proposed.isSameGroup = isSameGroup
        proposed.legacy = pendingLegacy(read.legacy, isFounding: isFounding, isSameGroup: isSameGroup, state: state, environment: environment)
        proposed.phase = .asking
        if let question = SyncJoin.question(pending: proposed, state: draft.state, restrictedTo: nil, environment: environment) {
            proposed.shown = question.shown
            draft.state.pendingJoin = proposed
            draft.state.session.waitingFiles = 0
            return
        }
        commitTentative(&draft.state, pending: proposed, snapshot: snapshot, environment: environment)
        finishCommit(&draft, pending: proposed, environment: environment)
    }

    /// What the legacy file offers the join: its units when this Mac founds a group, and its
    /// digest in any case, so a later change shows the status line.
    private static func pendingLegacy(
        _ outcome: SyncLegacyOutcome?,
        isFounding: Bool,
        isSameGroup: Bool,
        state: SyncState,
        environment: SyncEnvironment
    ) -> SyncPendingLegacy? {
        switch outcome {
        case nil:
            return nil
        case .file(let file)?:
            var units: [SyncUnitKey: SyncValue] = [:]
            // Only when the folder holds no device file, and not this Mac's own older state.
            if isFounding, !isSameGroup, !file.isWritten(byLegacyDeviceID: state.legacy.legacyDeviceID) {
                units = SyncJoin.usableLegacyUnits(file.settings, environment: environment)
            }
            return SyncPendingLegacy(units: units, modified: file.modified, digest: file.identityDigest)
        case .absent?, .refused?:
            return SyncPendingLegacy(units: [:], modified: nil, digest: .unset)
        }
    }

    /// The replica and the units after the commit, before the rows are answered.
    static func commitTentative(_ state: inout SyncState, pending: SyncPendingJoin, snapshot: SyncSnapshot, environment: SyncEnvironment) {
        state.replica = pending.replica
        if pending.isSameGroup {
            let plan = SyncPlan.plan(state: state, snapshot: snapshot, environment: environment)
            state = SyncCapture.settle(plan, snapshot: snapshot, state: state, environment: environment)
        } else {
            SyncJoin.settleDotless(&state, snapshot: snapshot, legacy: pending.legacy, skipping: Set(pending.shown.keys), environment: environment)
        }
    }

    /// The commit: the folder is the sync folder, what the legacy file and the tripwire held is
    /// recorded as seen, and the new entries are published.
    static func finishCommit(_ draft: inout SyncDraft, pending: SyncPendingJoin, environment: SyncEnvironment) {
        draft.state.isEnabled = true
        draft.state.pendingJoin = nil
        draft.state.captureDeferred = false
        draft.state.session.isTrusted = true
        draft.state.session.waitingFiles = 0
        draft.state.legacy.lastSyncedSeen = draft.state.session.lastSyncedSeen
        if let legacy = pending.legacy {
            draft.state.legacy.foundingDigest = legacy.digest
            draft.state.legacy.lastLegacyChange = nil
        }
        if let folder = pending.folderIdentity {
            draft.effects.append(.commitFolder(folder))
        }
        draft.effects.append(.schedule(.periodic, after: SyncTimer.periodic.delay))
        // What the user changed while the join waited is captured now.
        capture(&draft, environment: environment)
        publish(&draft, trigger: .ownChange, environment: environment)
    }

    /// Use or Keep at a join: the commit and the answer in one step.
    static func answerJoin(_ request: SyncAnswerRequest, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard let pending = draft.state.pendingJoin, pending.phase == .asking else {
            return
        }
        let snapshot = draft.state.session.snapshot ?? SyncSnapshot()
        var state = draft.state
        commitTentative(&state, pending: pending, snapshot: snapshot, environment: environment)
        // Refused (a row has no choice): the join stays as it was.
        guard let write = writeAnswers(request, state: &state, snapshot: snapshot, environment: environment) else {
            return
        }
        draft.state = state
        draft.applies = write.applies
        finishCommit(&draft, pending: pending, environment: environment)
        if !write.applies.isEmpty {
            draft.effects.append(.relaunch)
        }
    }
}
