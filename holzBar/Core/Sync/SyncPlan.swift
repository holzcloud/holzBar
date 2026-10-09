//
//  SyncPlan.swift
//  holzBar
//

import Foundation

/// What a unit needs, given the entries Sigma holds and the local value (analysis section 4.6.3).
nonisolated enum SyncUnitOutcome: Hashable, Sendable {
    /// The single live value is the local value: adopt its dots, silently.
    case equal
    /// The single live value differs and nothing here is in its way: applied at launch or by
    /// Restart.
    case fastForward
    /// The single live value differs from a value that was here before sync: a question.
    case preRow
    /// Two or more live values. It is this Mac's question when this Mac or one of its earlier
    /// identities minted one of them, otherwise a bystander conflict.
    case conflict(mine: Bool)
    /// A fast-forward that would give two hotkeys the same key combination: never applied.
    case clash
    /// The local value cannot be published, so nothing replaces it.
    case protectedLocalOnly
    /// The live value cannot be used by this build (invalid, over its cap).
    case notApplicable
    /// The unit's key is mapped to another key here: relayed only.
    case aliased
    /// A value that was here before sync and the group has none: published as this Mac's entry.
    case publishPreexisting
    /// This Mac's own entry is the only live one and the local value has changed since it was captured: a change of
    /// the user's that waits for its capture. Nothing is applied over it and no hint shows.
    case pendingLocal
    /// A unit of a family this Mac neither authors nor applies (the macOS 27 families on macOS 26):
    /// it stays in the replica and in the file byte for byte, and never reaches the hint, the
    /// questions or the status lines.
    case relayOnly
}

/// Hotkey units that cannot all apply because they would share a key combination.
nonisolated struct SyncClash: Hashable, Sendable {
    /// The units in the clash, sorted: the fast-forwards and the local hotkeys they collide with.
    let units: [SyncUnitKey]
}

/// What every synced unit needs, computed only from the persisted replica, the snapshot and
/// `applied`, so it is the same before and after a relaunch.
nonisolated struct SyncPlan: Sendable {
    /// The outcome of every unit that has one; units this build does not know, or does not
    /// author here, have none and are relayed untouched.
    let outcomes: [SyncUnitKey: SyncUnitOutcome]
    /// The single live payload of every fast-forward unit.
    let fastForwardPayloads: [SyncUnitKey: SyncPayload]
    /// The clash rows.
    let clashes: [SyncClash]

    /// The units that wait for a restart, sorted.
    var fastForwards: [SyncUnitKey] {
        outcomes.keys.sorted().filter { outcomes[$0] == .fastForward }
    }

    /// The rows of the sheet: this Mac's conflicts, the clashes and the pre rows.
    var questionRows: Int {
        // sync-lint: ordered only the count is used
        outcomes.values.filter { outcome in
            switch outcome {
            case .conflict(mine: true), .preRow:
                true
            default:
                false
            }
        }.count + clashes.count
    }

    /// The conflicts between other Macs.
    var bystanderRows: Int {
        // sync-lint: ordered only the count is used
        outcomes.values.filter { $0 == .conflict(mine: false) }.count
    }

    /// Whether a live value cannot be used by this build.
    var hasUnusableValue: Bool {
        outcomes.values.contains(.notApplicable)
    }

    /// Choose Settings when a conflict, a clash or a pre row is this Mac's, otherwise Restart
    /// when a fast-forward waits, otherwise nothing. Bystander conflicts give no hint.
    var hint: SyncHint? {
        if questionRows > 0 {
            return .choose
        }
        return fastForwards.isEmpty ? nil : .restart
    }

    // MARK: Planning

    /// Plans every unit of the replica and of the snapshot.
    static func plan(state: SyncState, snapshot: SyncSnapshot, environment: SyncEnvironment) -> SyncPlan {
        let table = environment.table
        var keys = Set(state.replica.registers.keys)
        keys.formUnion(snapshot.values.keys)
        var outcomes: [SyncUnitKey: SyncUnitOutcome] = [:]
        var payloads: [SyncUnitKey: SyncPayload] = [:]
        for key in keys.sorted() {
            guard let descriptor = table.descriptor(for: key), !descriptor.isSet else {
                continue
            }
            guard table.isApplicableHere(key, generation: environment.generation) else {
                outcomes[key] = .relayOnly
                continue
            }
            if snapshot.aliased.contains(key) {
                outcomes[key] = .aliased
                continue
            }
            let local = SyncProjection.localValue(key, in: snapshot.values, table: table)
            let live = state.replica.live(key)
            guard !live.isEmpty else {
                if local != nil, state.localOrigin[key] == .preexisting, state.localOnly[key] == nil {
                    outcomes[key] = .publishPreexisting
                }
                continue
            }
            let values = state.replica.distinctValues(key)
            guard values.count == 1 else {
                // This Mac takes part when it minted one of the values, or holds one of them as
                // its applied value (it adopted a sibling at a join). An applied deletion is no value
                // its user ever saw, so it makes this Mac no party.
                let applied = Set(state.applied[key] ?? [])
                // An application with no stored section is in the visible section, which is a value only in the group's entries
                // (D-04): a Mac that matches an entry of that value by holding nothing took no part in its making.
                let isImplicitVisible = SyncLayout27.isIntentCaptured(key) && snapshot.values[key] == nil
                outcomes[key] = .conflict(mine: live.contains { entry in
                    state.isOwn(entry.dot)
                        || (applied.contains(entry.dot) && entry.payload != .deleted && !(isImplicitVisible && entry.payload == .value(SyncLayout27.visible)))
                })
                continue
            }
            let payload = values[0]
            if SyncCapture.matches(payload, local: local, key: key, table: table) {
                outcomes[key] = .equal
            } else if case .value(let value) = payload, !descriptor.validate(key.itemName, value) || descriptor.isOverCap(value) {
                outcomes[key] = .notApplicable
            } else if SyncLayout27.isIntentCaptured(key), Set(live.map(\.dot)).isSubset(of: state.applied[key] ?? []) {
                // This Mac applied the entry: a local value that differs is holzBar's own store (a profile
                // bound to a Space, a displaced item), never a change of another Mac, so nothing waits (D-04).
                // A value the user marked as theirs (a move made while sync was off, or one that waited for a
                // state that could mint, 28-12) is no store of holzBar's: no other Mac holds anything newer than
                // the entry this Mac applied, so it is a newer change of that entry, published at the next join
                // instead of being settled as equal and left to diverge (found by A1 S-48). Where the group did
                // move on, an entry that is not applied is live and the unit falls through to the question below.
                if local != nil, state.localOrigin[key] == .preexisting, state.localOnly[key] == nil {
                    outcomes[key] = .publishPreexisting
                } else {
                    outcomes[key] = .equal
                }
            } else if state.localOnly[key] != nil {
                outcomes[key] = .protectedLocalOnly
            } else if local != nil, state.localOrigin[key] == .preexisting {
                outcomes[key] = .preRow
            } else if live.allSatisfy({ state.isOwn($0.dot) }), let baseline = state.baseline[key], (local?.digest ?? .unset) != baseline {
                // The only entries are this Mac's own and the local value moved on from what was last captured: a
                // change of the user's that the capture has not minted yet (it runs two seconds after the edit). It is
                // no change of another Mac, so nothing waits and no hint shows (found by A1 S-65).
                outcomes[key] = .pendingLocal
            } else {
                outcomes[key] = .fastForward
                payloads[key] = payload
            }
        }
        let clashes = clashes(fastForwards: payloads, snapshot: snapshot)
        for clash in clashes {
            // sync-lint: ordered the units of a clash are an array in key order
            for unit in clash.units where outcomes[unit] == .fastForward {
                outcomes[unit] = .clash
                payloads[unit] = nil
            }
        }
        return SyncPlan(outcomes: outcomes, fastForwardPayloads: payloads, clashes: clashes)
    }

    // MARK: Clash check

    /// Simulates applying the fast-forwards of the hotkeys together with the local hotkeys and
    /// returns the groups of units that would share a key combination. A group without a
    /// fast-forward is already how this Mac is, and not a clash.
    static func clashes(fastForwards: [SyncUnitKey: SyncPayload], snapshot: SyncSnapshot) -> [SyncClash] {
        let family = Defaults.Key.hotkeys.rawValue
        var combinations: [SyncUnitKey: [Int]] = [:]
        // sync-lint: ordered every unit is assigned to its own key of a dictionary
        for (key, value) in snapshot.values {
            if case .split(family, _) = key, let combination = combination(of: value) {
                combinations[key] = combination
            }
        }
        var incoming = Set<SyncUnitKey>()
        // sync-lint: ordered every unit is assigned to its own key of a dictionary or goes into a set
        for (key, payload) in fastForwards {
            guard case .split(family, _) = key else {
                continue
            }
            switch payload {
            case .deleted:
                combinations[key] = nil
            case .value(let value):
                combinations[key] = combination(of: value)
                if combinations[key] != nil {
                    incoming.insert(key)
                }
            }
        }
        var groups: [[Int]: [SyncUnitKey]] = [:]
        for key in combinations.keys.sorted() {
            if let combination = combinations[key] {
                groups[combination, default: []].append(key)
            }
        }
        var clashes: [SyncClash] = []
        for combination in groups.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let units = groups[combination] ?? []
            if units.count > 1, units.contains(where: incoming.contains) {
                clashes.append(SyncClash(units: units))
            }
        }
        return clashes
    }

    /// The key combination a stored hotkey holds, or `nil` for a cleared or unreadable one.
    private static func combination(of value: SyncValue) -> [Int]? {
        guard case .data(let data) = value, let decoded = HotkeyStorage.decode(data) else {
            return nil
        }
        return [decoded.key, decoded.modifiers]
    }
}
