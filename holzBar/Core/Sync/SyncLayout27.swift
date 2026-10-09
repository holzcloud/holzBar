//
//  SyncLayout27.swift
//  holzBar
//

import Foundation

/// One change of one unit that the user made, as the app reports it: where it came from and
/// where it went. The engine mints an entry for it; it never looks at the defaults to find out.
nonisolated struct SyncUnitIntent: Hashable, Sendable {
    /// The unit the user changed.
    let unit: SyncUnitKey
    /// This Mac's value before the change. For an application of `l27` that had no stored
    /// section this is ``SyncLayout27/visible``, never `nil`.
    let from: SyncValue?
    /// What the user set the unit to.
    let to: SyncPayload

    init(unit: SyncUnitKey, from: SyncValue?, to: SyncPayload) {
        self.unit = unit
        self.from = from
        self.to = to
    }

    /// Whether the change leaves the unit as it was.
    var isNoChange: Bool {
        switch to {
        case .value(let value):
            value == from
        case .deleted:
            from == nil
        }
    }
}

/// What the user did that sync must capture without looking at the defaults (decision D-04).
///
/// holzBar's own automatic stores write the same keys as the user's moves, so for the
/// families `l27` and `prof` a change of the defaults is not evidence of a change by the user.
nonisolated enum SyncIntent: Hashable, Sendable {
    /// One user action that changed these units: a move in the Layout pane, the entries a
    /// profile the user applied changes, the units an import sets or removes, a profile the
    /// user saved, renamed or deleted.
    case userSet([SyncUnitIntent])
}

/// The rules of the macOS 27 families: the arrangement `l27/<bundleID>`, the layout profiles
/// `prof/<profileID>` and the known applications `known27`.
///
/// Only a Mac of macOS 27 authors or applies them; a Mac of macOS 26 relays them unchanged
/// (decisions D-04 to D-06). The functions here are pure: they turn what the app saw into
/// ``SyncUnitIntent`` values and answer which applications automatic stores must leave alone.
nonisolated enum SyncLayout27 {
    /// The explicit value of an application in the visible section. In the defaults a visible
    /// application has no entry, but a value of the unit is never an absence (D-04).
    static let visible = SyncValue.integer(0)

    /// Whether the unit's changes are captured from intent events and never by diffing the
    /// defaults: the families `l27` and `prof`.
    static func isIntentCaptured(_ key: SyncUnitKey) -> Bool {
        guard case .split(let family, _) = key else {
            return false
        }
        return family == SyncUnitTable.layout27Family || family == SyncUnitTable.profilesFamily
    }

    // MARK: Intents

    /// The intent of moving one application from one section to another, `nil` when the
    /// section did not change. A `nil` section is the visible one.
    static func moveIntent(bundleID: String, from: SyncValue?, to: SyncValue?) -> SyncUnitIntent? {
        let before = from ?? visible
        let after = to ?? visible
        guard before != after else {
            return nil
        }
        return SyncUnitIntent(unit: .split(family: SyncUnitTable.layout27Family, item: bundleID), from: before, to: .value(after))
    }

    /// One intent per application whose section changed, in sorted bundle-ID order. An absent
    /// entry is the visible section on both sides, and the new value is explicit in both
    /// directions, so moving an application back to visible is the value `0`, not a deletion.
    static func layoutIntents(old: [String: SyncValue], new: [String: SyncValue]) -> [SyncUnitIntent] {
        let bundles = Set(old.keys).union(new.keys).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return bundles.compactMap { moveIntent(bundleID: $0, from: old[$0], to: new[$0]) }
    }

    /// One intent per profile that was created, changed or deleted, in sorted profile-ID order.
    /// A rename is one change of one ID, never a deletion and a creation.
    static func profileIntents(old: [String: SyncValue], new: [String: SyncValue]) -> [SyncUnitIntent] {
        let identifiers = Set(old.keys).union(new.keys).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var intents: [SyncUnitIntent] = []
        for identifier in identifiers {
            let unit = SyncUnitKey.split(family: SyncUnitTable.profilesFamily, item: identifier)
            switch (old[identifier], new[identifier]) {
            case (let before?, let after?):
                if before != after {
                    intents.append(SyncUnitIntent(unit: unit, from: before, to: .value(after)))
                }
            case (nil, let after?):
                intents.append(SyncUnitIntent(unit: unit, from: nil, to: .value(after)))
            case (let before?, nil):
                intents.append(SyncUnitIntent(unit: unit, from: before, to: .deleted))
            case (nil, nil):
                break
            }
        }
        return intents
    }

    /// The value of the unit `prof/<profileID>`: the three fields of a profile that sync. The
    /// known applications are a sorted, unique array and are left out when `nil`.
    static func profileValue(name: String, applicationSections: [String: Int], knownApplications: [String]?) -> SyncValue {
        var fields: [String: SyncValue] = [
            "name": .string(name),
            "applicationSections": .dictionary(applicationSections.mapValues { .integer(Int64($0)) }),
        ]
        if let knownApplications {
            let sorted = Set(knownApplications).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            fields["knownApplications"] = .array(sorted.map { .string($0) })
        }
        return .dictionary(fields)
    }

    // MARK: Automatic stores

    /// The applications whose arrangement an automatic store must leave alone: the bundle IDs
    /// whose `l27` unit has applied intent, an entry that the user made or the group made
    /// that this Mac holds. Seeding and the placement of a new application fill only the
    /// applications that are not in this set (INV-A1 to INV-A3).
    static func protectedApplications(in state: SyncState) -> Set<String> {
        var applications: Set<String> = []
        // sync-lint: ordered applications go into a set
        for (key, dots) in state.applied where !dots.isEmpty {
            if case .split(let family, let item) = key, family == SyncUnitTable.layout27Family {
                applications.insert(item)
            }
        }
        return applications
    }

    // MARK: Upgrade

    /// Takes note of the macOS generation of this launch. After an upgrade from macOS 26 to
    /// macOS 27 the arrangement in the defaults was copied or seeded by holzBar, not arranged
    /// by the user: every entry of the families that came into scope without applied intent is
    /// marked `automatic`, so the group's values reach this Mac silently over them, and only an
    /// application the user arranges after the upgrade can conflict (INV-L6). The state is never
    /// emptied or removed.
    static func noteSystemGeneration(_ state: inout SyncState, snapshot: SyncSnapshot, environment: SyncEnvironment) {
        guard state.systemGeneration != environment.generation else {
            return
        }
        if state.systemGeneration == .g26, environment.generation == .g27 {
            for key in snapshot.values.keys.sorted() where isIntentCaptured(key) && (state.applied[key] ?? []).isEmpty {
                state.localOrigin[key] = .automatic
            }
        }
        state.systemGeneration = environment.generation
    }
}

// MARK: - Engine

nonisolated extension SyncEngine {
    /// The user changed units of the macOS 27 families. Each unit this Mac authors gets one
    /// entry that supersedes what this Mac had applied, and the write follows after the usual
    /// debounce. While the state cannot mint (a join waits, capture is deferred) the changes wait
    /// in the session, because an intent cannot be found again by comparing the defaults.
    static func onIntent(_ intent: SyncIntent, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard case .userSet(let intents) = intent else {
            return
        }
        // A value the user set is no longer one that holzBar placed itself.
        for change in intents where draft.state.localOrigin[change.unit] == .automatic {
            draft.state.localOrigin[change.unit] = nil
        }
        guard draft.state.isEnabled || draft.state.pendingJoin != nil else {
            // Sync is off: nothing is minted, but what the user set is a value of theirs that was there before the
            // next join. The join asks about it where the group differs and publishes it where the group has none
            // (D-10); without the mark a group that moved on meanwhile would replace it silently at Restart.
            for change in intents where !change.isNoChange && environment.table.isAuthoredHere(change.unit, generation: environment.generation) {
                if isValueOfTheUser(change.to) {
                    draft.state.localOrigin[change.unit] = .preexisting
                }
            }
            // The state keeps what it knew when sync went off: what the user did since (a removed profile, a moved application) is
            // minted when sync is on again, as one change per unit: the first value the unit had and the last the user set.
            for change in intents where environment.table.isAuthoredHere(change.unit, generation: environment.generation) {
                var merged = change
                // A join that waited queued each change of its own, so a unit can have several waiting: they all become this one.
                if let earlier = draft.state.queuedIntents.firstIndex(where: { $0.unit == change.unit }) {
                    merged = SyncUnitIntent(unit: change.unit, from: draft.state.queuedIntents[earlier].from, to: change.to)
                    draft.state.queuedIntents.removeAll { $0.unit == change.unit }
                }
                if !merged.isNoChange {
                    draft.state.queuedIntents.append(merged)
                }
                // A change that leaves the unit as it was or deletes it leaves no value of the user's there to mark: the mark of the change it replaces would otherwise stay and make a value that holzBar places later look
                // like the user's.
                if merged.isNoChange || !isValueOfTheUser(merged.to), draft.state.localOrigin[change.unit] == .preexisting {
                    draft.state.localOrigin[change.unit] = nil
                }
            }
            return
        }
        draft.state.queuedIntents += intents
        drainIntents(&draft, environment: environment)
        // An intent that cannot be minted yet waits in the session, which a crash loses, and an intent cannot be found
        // again by comparing the defaults. What the user set stays a value of theirs in the state, which survives: once
        // the state can mint, the entry replaces the mark; if the session is lost first, the value is asked about where
        // the group differs and published where it has none.
        for change in draft.state.queuedIntents where !change.isNoChange && environment.table.isAuthoredHere(change.unit, generation: environment.generation) {
            if isValueOfTheUser(change.to) {
                draft.state.localOrigin[change.unit] = .preexisting
            } else if draft.state.localOrigin[change.unit] == .preexisting {
                // The last word of the user about the unit is a deletion, or the visible section: no value of theirs is left to mark.
                draft.state.localOrigin[change.unit] = nil
            }
        }
        if draft.state.isEnabled {
            draft.effects.append(.schedule(.capture, after: SyncTimer.capture.delay))
        }
    }

    /// Whether an intent's new state of a unit is a value of the user's to protect: a value (the visible section included, which the
    /// user chose), not a deletion.
    private static func isValueOfTheUser(_ payload: SyncPayload) -> Bool {
        if case .value = payload {
            return true
        }
        return false
    }

    /// Mints the queued intents when the state can mint.
    static func drainIntents(_ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard !draft.state.queuedIntents.isEmpty, draft.state.isEnabled, draft.state.pendingJoin == nil else {
            return
        }
        if !draft.state.session.isTrusted, environment.guards.contains(.trustedState) {
            return
        }
        let queued = draft.state.queuedIntents
        draft.state.queuedIntents = []
        SyncCapture.capture(intents: queued, state: &draft.state, environment: environment)
    }

    /// Adds the applications this Mac knows to the set `known27` of the replica (D-06). The
    /// union never removes an element, never mints a dot and never causes a hint or a question;
    /// the change is published at the latest after an hour or rides along with the next write.
    static func learnKnownApplications(_ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard
            environment.table.isKnownApplicationsApplicable(generation: environment.generation),
            draft.state.isEnabled, draft.state.pendingJoin == nil,
            draft.state.session.isTrusted || !environment.guards.contains(.trustedState),
            let snapshot = draft.state.session.snapshot
        else {
            return
        }
        let name = SyncUnitTable.knownApplicationsSet
        let replica = draft.state.replica
        let current = replica.sets[name] ?? []
        var sets = replica.sets
        sets[name] = current + snapshot.known27.filter(SyncUnitTable.isItemKey)
        let joined = SyncReplica(context: replica.context, registers: replica.registers, sets: sets)
        guard let union = joined.sets[name], union != current else {
            return
        }
        draft.state.replica = joined
        if !draft.state.session.isLearnedTimerPending {
            draft.state.session.isLearnedTimerPending = true
            draft.effects.append(.schedule(.learned, after: SyncTimer.learned.delay))
        }
    }

    /// Asks the host to add what the group knows to this Mac's `KnownApplications27`. Only at
    /// launch and at Restart, never as a hint, a question or a reason to restart (D-06).
    static func applyKnownApplications(_ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard
            environment.table.isKnownApplicationsApplicable(generation: environment.generation),
            var snapshot = draft.state.session.snapshot
        else {
            return
        }
        let known = Set(snapshot.known27)
        let missing = (draft.state.replica.sets[SyncUnitTable.knownApplicationsSet] ?? []).filter { !known.contains($0) }
        guard !missing.isEmpty else {
            return
        }
        snapshot.known27 = Array(known.union(missing)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        draft.state.session.snapshot = snapshot
        draft.effects.append(.applyKnownApplications(missing))
    }
}
