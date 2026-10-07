//
//  SyncCapture.swift
//  holzBar
//

import Foundation

/// Turns a change of the local settings into an entry (analysis section 4.6.2).
///
/// Capture is diff-based: it compares the normalized local value of every unit with the
/// baseline, the value as last captured or applied. So it sees every way the user changes a
/// setting (the controls, a hotkey, Import, `defaults write`) and none that the user did not
/// make, because holzBar's own load-time rewrites normalize to the same value.
nonisolated enum SyncCapture {
    // MARK: Capture

    /// The state after capturing `snapshot`: one new entry per unit the user changed, with the
    /// counters, `applied`, `baseline` and the context moved. Nothing else changes, and nothing
    /// is minted for a state that is not trusted.
    static func capture(_ snapshot: SyncSnapshot, state: SyncState, environment: SyncEnvironment) -> SyncState {
        if !state.session.isTrusted, environment.guards.contains(.trustedState) {
            return state
        }
        var state = state
        var keys = Set(snapshot.values.keys)
        keys.formUnion(state.baseline.keys)
        keys.formUnion(state.replica.registers.keys)
        for key in keys.sorted() {
            guard
                let descriptor = environment.table.descriptor(for: key),
                !descriptor.isSet,
                environment.table.isAuthoredHere(key, generation: environment.generation),
                !snapshot.aliased.contains(key)
            else {
                continue
            }
            captureUnit(key, descriptor, snapshot: snapshot, state: &state, environment: environment)
        }
        return state
    }

    private static func captureUnit(
        _ key: SyncUnitKey,
        _ descriptor: SyncUnitDescriptor,
        snapshot: SyncSnapshot,
        state: inout SyncState,
        environment: SyncEnvironment
    ) {
        let local = SyncProjection.localValue(key, in: snapshot.values, table: environment.table)
        let digest = local?.digest ?? .unset
        let item = key.itemName
        let baseline: SyncDigest
        if let known = state.baseline[key] {
            baseline = known
        } else if descriptor.isFamily {
            // A family is known whole when Sigma is made, so an item it has no baseline for
            // had no value then.
            baseline = .unset
        } else if local != nil {
            // A unit with no baseline is never captured: its present value is a question for
            // the plan (published where the group has none, asked where it differs).
            if state.localOrigin[key] == nil {
                state.localOrigin[key] = .preexisting
            }
            return
        } else if environment.guards.contains(.absentMeansNoValue) {
            return
        } else {
            // Control engine: absence counts as a value, so a Mac that never had the key
            // deletes it for everyone.
            baseline = SyncDigest.hash(Array("never present".utf8))
        }
        if digest == baseline {
            return
        }
        if let local, local == SyncProjection.unrepresentable || !descriptor.validate(item, local) {
            state.localOnly[key] = .invalid
            state.baseline[key] = digest
            return
        }
        if let local, descriptor.isOverCap(local) {
            state.localOnly[key] = .oversize
            state.baseline[key] = digest
            return
        }
        state.localOnly[key] = nil
        let payload: SyncPayload = local.map { .value($0) } ?? .deleted
        let live = state.replica.live(key)
        let values = state.replica.distinctValues(key)
        if values.count == 1, matches(values[0], local: local, key: key, table: environment.table) {
            // A finished apply, or the user chose that value.
            state.applied[key] = live.map(\.dot)
            state.baseline[key] = digest
            state.localOrigin[key] = nil
            return
        }
        _ = mint(key, payload: payload, digest: digest, state: &state, environment: environment)
    }

    /// Whether `payload` is what the defaults hold as `local`, compared as this build normalizes
    /// it. A deletion equals an absent value, and for the macOS 27 arrangement a visible one.
    static func matches(_ payload: SyncPayload, local: SyncValue?, key: SyncUnitKey, table: SyncUnitTable) -> Bool {
        switch payload {
        case .value(let value):
            return table.normalized(value, for: key) == local
        case .deleted:
            if case .split(let family, _) = key, family == SyncUnitTable.layout27Family {
                return local == nil || local == .integer(0)
            }
            return local == nil
        }
    }

    /// Mints an entry of this Mac for `key` that supersedes the dots this Mac had applied (all
    /// of them without the applied-context guard), and records it as applied and baseline.
    ///
    /// An answer passes `superseding`: exactly the dots its sheet showed, so an entry that
    /// arrived after the sheet opened survives as a sibling and is asked about again.
    ///
    /// - Returns: Whether an entry was minted. A counter above 2^34 mints nothing and marks the
    ///   unit invalid, because this Mac has to re-identify before it can mint again.
    @discardableResult
    static func mint(
        _ key: SyncUnitKey,
        payload: SyncPayload,
        digest: SyncDigest,
        state: inout SyncState,
        environment: SyncEnvironment,
        superseding shown: Set<SyncDot>? = nil
    ) -> Bool {
        guard
            let counter = SyncIdentity.nextCounter(
                stateCounter: state.counter,
                mirror: environment.counterFloors.mirror,
                highWater: environment.counterFloors.highWater,
                unixSeconds: environment.unixSeconds,
                maxSeenSelf: state.replica.context[state.mac]
            )
        else {
            state.localOnly[key] = .invalid
            return false
        }
        let dot = SyncDot(mac: state.mac, n: counter)
        let entry = SyncEntry(dot: dot, at: environment.now, payload: payload)
        let superseded: Set<SyncDot> = if let shown {
            shown
        } else if environment.guards.contains(.appliedContext) {
            Set(state.applied[key] ?? [])
        } else {
            Set(state.replica.live(key).map(\.dot))
        }
        var registers = state.replica.registers
        registers[key] = state.replica.live(key).filter { !superseded.contains($0.dot) } + [entry]
        state.replica = SyncReplica(context: state.replica.context.adding(dot), registers: registers, sets: state.replica.sets)
        state.counter = counter
        state.applied[key] = [dot]
        state.baseline[key] = digest
        state.localOnly[key] = nil
        state.localOrigin[key] = nil
        return true
    }

    // MARK: After a plan

    /// The state after the silent consequences of `plan`: a unit whose single live value equals
    /// the local value adopts its dots (INV-P2), and a value that was there before sync is
    /// published where the group has none.
    static func settle(_ plan: SyncPlan, snapshot: SyncSnapshot, state: SyncState, environment: SyncEnvironment) -> SyncState {
        var state = state
        for key in plan.outcomes.keys.sorted() {
            let local = SyncProjection.localValue(key, in: snapshot.values, table: environment.table)
            switch plan.outcomes[key] {
            case .equal?:
                state.applied[key] = state.replica.live(key).map(\.dot)
                state.baseline[key] = local?.digest ?? .unset
                state.localOrigin[key] = nil
            case .publishPreexisting?:
                if let local {
                    mint(key, payload: .value(local), digest: local.digest, state: &state, environment: environment)
                }
            default:
                break
            }
        }
        return state
    }

    /// The state after the defaults took `changes`: each unit holds the live dots as applied and
    /// the value the defaults now hold as baseline.
    static func applied(_ changes: [SyncUnitKey: SyncPayload], snapshot: SyncSnapshot, state: SyncState, environment: SyncEnvironment) -> SyncState {
        var state = state
        let after = snapshot.applying(changes, table: environment.table)
        for key in changes.keys.sorted() {
            let local = SyncProjection.localValue(key, in: after.values, table: environment.table)
            state.applied[key] = state.replica.live(key).map(\.dot)
            state.baseline[key] = local?.digest ?? .unset
            state.localOrigin[key] = nil
        }
        state.session.snapshot = after
        return state
    }
}

nonisolated extension SyncUnitKey {
    /// The item of a split unit, `nil` for a whole unit.
    var itemName: String? {
        switch self {
        case .whole:
            nil
        case .split(_, let item):
            item
        }
    }
}
