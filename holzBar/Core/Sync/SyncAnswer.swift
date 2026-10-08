//
//  SyncAnswer.swift
//  holzBar
//

import Foundation

// MARK: - The question

/// What a sheet asks about.
nonisolated enum SyncQuestionKind: Hashable, Sendable {
    /// This Mac's conflicts, clashes and values that were here before sync.
    case running
    /// The differences between this Mac and the folder at a join.
    case joining
    /// Conflicts between other Macs, which this Mac may settle on their behalf.
    case bystander
}

/// Which question the host asks for.
nonisolated enum SyncQuestionScope: Hashable, Sendable {
    /// This Mac's own question: the join's, or the running one.
    case mine
    /// The conflicts between other Macs.
    case bystander
}

/// How a row is answered.
nonisolated enum SyncRowStyle: Hashable, Sendable {
    /// This Mac's value against one other value.
    case twoWay
    /// Three or more values: a pop-up lists them, and the user picks one with no default.
    case multi
    /// Two hotkeys that would share a key combination; `partner` is the other unit.
    case clash(partner: SyncUnitKey)
    /// A conflict this Mac has no part in: every value is listed, and the user picks one.
    case bystander
}

/// One value in a row. The date is the minting Mac's and is shown only; the other Mac is
/// never named.
nonisolated struct SyncRowValue: Hashable, Sendable {
    /// Where the value comes from.
    enum Source: Hashable, Sendable {
        /// An entry of the replica, by its dot.
        case entry(SyncDot)
        /// The legacy file of 0.0.6 and 0.0.7-beta1, at a founding join.
        case legacyFile
        /// A value of this Mac that has no entry (yet).
        case thisMac
    }

    var value: SyncPayload
    var at: Date
    var source: Source
}

/// One setting of the sheet.
nonisolated struct SyncRow: Hashable, Sendable {
    var unit: SyncUnitKey
    /// This Mac's value, `nil` when this Mac holds none.
    var local: SyncRowValue?
    /// The other values: one for a two-way row and a clash, every value for a multi or
    /// bystander row. Never empty.
    var folder: [SyncRowValue]
    var style: SyncRowStyle
}

/// What a sheet shows: the rows, and for each unit the exact dots the sheet displayed, so an
/// answer supersedes only those (D-07).
nonisolated struct SyncQuestion: Hashable, Sendable {
    var kind: SyncQuestionKind
    var rows: [SyncRow]
    var shown: [SyncUnitKey: [SyncDot]]
}

/// The button the user pressed.
nonisolated enum SyncAnswerButton: Hashable, Sendable {
    /// Use Settings from Sync Folder.
    case use
    /// Keep This Mac's Settings.
    case keep
    /// Later: nothing is written, and the hint hides until the next launch.
    case later
    /// Cancel, at a join.
    case cancel
    /// The pick of every row, for rows that need an explicit choice.
    case useChosen
}

/// An answer: the button, the pop-up picks and the question as it was shown.
nonisolated struct SyncAnswerRequest: Hashable, Sendable {
    var button: SyncAnswerButton
    /// For a pop-up row, the index in ``SyncRow/folder`` of the value the user picked.
    var choices: [SyncUnitKey: Int]
    var question: SyncQuestion

    init(button: SyncAnswerButton, choices: [SyncUnitKey: Int] = [:], question: SyncQuestion) {
        self.button = button
        self.choices = choices
        self.question = question
    }
}

// MARK: - Rows

/// Builds the rows of the running question from the plan.
nonisolated enum SyncRows {
    /// The distinct values of `entries`, each with its first entry's dot and date.
    static func values(of entries: [SyncEntry]) -> [SyncRowValue] {
        var seen = Set<SyncDigest>()
        var result: [SyncRowValue] = []
        for entry in entries where seen.insert(entry.payload.digest).inserted {
            result.append(SyncRowValue(value: entry.payload, at: entry.at, source: .entry(entry.dot)))
        }
        return result
    }

    /// This Mac's value of `key`, which has no entry.
    static func local(_ key: SyncUnitKey, snapshot: SyncSnapshot, environment: SyncEnvironment) -> SyncRowValue? {
        SyncProjection.localValue(key, in: snapshot.values, table: environment.table).map {
            SyncRowValue(value: .value($0), at: environment.now, source: .thisMac)
        }
    }

    /// The rows of this Mac's own question: its conflicts, its clashes and the values that
    /// were here before sync and differ from the group's. Sorted by unit.
    static func running(state: SyncState, plan: SyncPlan, snapshot: SyncSnapshot, environment: SyncEnvironment) -> [SyncRow] {
        var rows: [SyncRow] = []
        for key in plan.outcomes.keys.sorted() {
            switch plan.outcomes[key] {
            case .conflict(mine: true)?:
                if let row = conflictRow(key, state: state) {
                    rows.append(row)
                }
            case .preRow?:
                rows.append(SyncRow(
                    unit: key,
                    local: local(key, snapshot: snapshot, environment: environment),
                    folder: values(of: state.replica.live(key)),
                    style: .twoWay
                ))
            case .clash?:
                if let group = plan.clashes.first(where: { $0.units.contains(key) }), let partner = group.units.first(where: { $0 != key }) {
                    rows.append(SyncRow(
                        unit: key,
                        local: local(key, snapshot: snapshot, environment: environment),
                        folder: values(of: state.replica.live(key)),
                        style: .clash(partner: partner)
                    ))
                }
            default:
                break
            }
        }
        return rows
    }

    /// The rows of the conflicts between other Macs: every value, no default. Sorted by unit.
    static func bystander(state: SyncState, plan: SyncPlan, snapshot: SyncSnapshot, environment: SyncEnvironment) -> [SyncRow] {
        plan.outcomes.keys.sorted().compactMap { key in
            guard plan.outcomes[key] == .conflict(mine: false) else {
                return nil
            }
            return SyncRow(
                unit: key,
                local: local(key, snapshot: snapshot, environment: environment),
                folder: values(of: state.replica.live(key)),
                style: .bystander
            )
        }
    }

    /// A conflict this Mac takes part in: its own value against the others'.
    private static func conflictRow(_ key: SyncUnitKey, state: SyncState) -> SyncRow? {
        let live = state.replica.live(key)
        let applied = Set(state.applied[key] ?? [])
        let mine = live.filter { state.isOwn($0.dot.mac) || applied.contains($0.dot) }
        guard let first = mine.first else {
            return nil
        }
        let all = values(of: live)
        let local = SyncRowValue(value: first.payload, at: first.at, source: .entry(first.dot))
        if all.count == 2, Set(mine.map(\.payload.digest)).count == 1 {
            return SyncRow(unit: key, local: local, folder: all.filter { $0.value.digest != first.payload.digest }, style: .twoWay)
        }
        return SyncRow(unit: key, local: local, folder: all, style: .multi)
    }

    /// The dots each row displays, per unit: the live dots of the unit and of a clash partner.
    static func shown(_ rows: [SyncRow], in replica: SyncReplica) -> [SyncUnitKey: [SyncDot]] {
        var result: [SyncUnitKey: [SyncDot]] = [:]
        for row in rows {
            result[row.unit] = replica.live(row.unit).map(\.dot)
            if case .clash(let partner) = row.style {
                result[partner] = replica.live(partner).map(\.dot)
            }
        }
        return result
    }
}

// MARK: - Engine

/// What an answer wrote.
nonisolated struct SyncAnswerWrite: Sendable {
    /// The values the defaults must take.
    var applies: [SyncUnitKey: SyncPayload] = [:]
    /// Whether any entry was minted.
    var wrote = false
}

nonisolated extension SyncEngine {
    /// The sheet's question, or `nil` when there is nothing to ask. It is computed from the
    /// persisted state only, so it is the same after a relaunch.
    static func question(for state: SyncState, scope: SyncQuestionScope, environment: SyncEnvironment) -> SyncQuestion? {
        switch scope {
        case .mine:
            if let pending = state.pendingJoin {
                guard pending.phase == .asking else {
                    return nil
                }
                return SyncJoin.question(pending: pending, state: state, restrictedTo: Set(pending.shown.keys), environment: environment)
            }
            guard state.isEnabled, let snapshot = state.session.snapshot else {
                return nil
            }
            let plan = SyncPlan.plan(state: state, snapshot: snapshot, environment: environment)
            let rows = SyncRows.running(state: state, plan: plan, snapshot: snapshot, environment: environment)
            guard !rows.isEmpty else {
                return nil
            }
            return SyncQuestion(kind: .running, rows: rows, shown: SyncRows.shown(rows, in: state.replica))
        case .bystander:
            guard state.isEnabled, state.pendingJoin == nil, let snapshot = state.session.snapshot else {
                return nil
            }
            let plan = SyncPlan.plan(state: state, snapshot: snapshot, environment: environment)
            let rows = SyncRows.bystander(state: state, plan: plan, snapshot: snapshot, environment: environment)
            guard !rows.isEmpty else {
                return nil
            }
            return SyncQuestion(kind: .bystander, rows: rows, shown: SyncRows.shown(rows, in: state.replica))
        }
    }

    // MARK: Answers

    /// An answer is a user act (analysis section 4.6.9): each row it decides gets one new entry
    /// with a fresh dot, which supersedes exactly the dots the sheet showed for it. An entry
    /// that arrived after the sheet opened is not among them and survives as a sibling.
    static func answer(_ request: SyncAnswerRequest, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        switch request.button {
        case .cancel:
            if draft.state.pendingJoin != nil {
                cancelJoin(&draft)
            }
        case .later:
            // Nothing is written; the siblings stay in every file, and the hint hides.
            if request.question.kind != .joining {
                draft.state.laterLaunch = draft.state.launchCount
            }
        case .use, .keep, .useChosen:
            if request.question.kind == .joining {
                answerJoin(request, &draft, environment: environment)
            } else {
                answerRunning(request, &draft, environment: environment)
            }
        }
    }

    private static func answerRunning(_ request: SyncAnswerRequest, _ draft: inout SyncDraft, environment: SyncEnvironment) {
        guard draft.state.isEnabled, draft.state.pendingJoin == nil else {
            return
        }
        // A change made just before the answer counts.
        capture(&draft, environment: environment)
        guard let snapshot = draft.state.session.snapshot else {
            return
        }
        var state = draft.state
        guard let write = writeAnswers(request, state: &state, snapshot: snapshot, environment: environment) else {
            return
        }
        draft.state = state
        guard write.wrote else {
            // Every row was decided elsewhere: nothing to write.
            return
        }
        draft.applies = write.applies
        publish(&draft, trigger: .ownChange, environment: environment)
        if !write.applies.isEmpty {
            draft.effects.append(.relaunch)
        } else if let current = draft.state.session.snapshot {
            // A relaunch applies the fast-forwards that still wait.
            let plan = SyncPlan.plan(state: draft.state, snapshot: current, environment: environment)
            if !plan.fastForwards.isEmpty {
                draft.effects.append(.relaunch)
            }
        }
    }

    /// Whether the dots a row showed are all still live.
    private static func isCurrent(_ row: SyncRow, question: SyncQuestion, state: SyncState) -> Bool {
        var units = [row.unit]
        if case .clash(let partner) = row.style {
            units.append(partner)
        }
        for unit in units {
            let live = Set(state.replica.live(unit).map(\.dot))
            if !Set(question.shown[unit] ?? []).isSubset(of: live) {
                return false
            }
        }
        return true
    }

    /// Whether an answer may write for the row: it supersedes dots only, never a unit that stays
    /// on this Mac (local-only), is mapped to another key here (aliased) or holds a value this
    /// build cannot use (not applicable).
    private static func isAnswerable(_ row: SyncRow, state: SyncState, snapshot: SyncSnapshot, environment: SyncEnvironment) -> Bool {
        var units = [row.unit]
        if case .clash(let partner) = row.style {
            units.append(partner)
        }
        for unit in units {
            guard
                state.localOnly[unit] == nil,
                !snapshot.aliased.contains(unit),
                environment.table.isApplicableHere(unit, generation: environment.generation)
            else {
                return false
            }
        }
        return row.folder.allSatisfy { SyncJoin.isUsable($0.value, key: row.unit, table: environment.table) }
    }

    /// The entries an answer writes, with their effect on `state`.
    ///
    /// - Returns: `nil` when the answer is refused: a row that needs a choice has none.
    static func writeAnswers(
        _ request: SyncAnswerRequest,
        state: inout SyncState,
        snapshot: SyncSnapshot,
        environment: SyncEnvironment
    ) -> SyncAnswerWrite? {
        let table = environment.table
        let question = request.question
        // A row decided elsewhere (its shown dots are gone) is left out of the answer.
        let rows = question.rows.filter {
            isCurrent($0, question: question, state: state) && isAnswerable($0, state: state, snapshot: snapshot, environment: environment)
        }
        for row in rows {
            switch row.style {
            case .multi, .bystander:
                guard let index = request.choices[row.unit], row.folder.indices.contains(index) else {
                    return nil
                }
            case .twoWay, .clash:
                if let index = request.choices[row.unit], !row.folder.indices.contains(index) {
                    return nil
                }
            }
        }
        func localPayload(_ unit: SyncUnitKey) -> SyncPayload {
            SyncProjection.localValue(unit, in: snapshot.values, table: table).map { .value($0) } ?? .deleted
        }
        var write = SyncAnswerWrite()
        for row in rows.sorted(by: { $0.unit < $1.unit }) {
            var targets: [(unit: SyncUnitKey, payload: SyncPayload)] = []
            switch row.style {
            case .clash(let partner):
                // Use: the other hotkey applies and this Mac's loses the combination. Keep: both
                // stay as this Mac has them, each as a fresh entry.
                let usesFolder = request.choices[row.unit] != nil || request.button != .keep
                targets.append((row.unit, usesFolder ? row.folder[0].value : localPayload(row.unit)))
                targets.append((partner, usesFolder ? .deleted : localPayload(partner)))
            case .twoWay, .multi, .bystander:
                if let index = request.choices[row.unit] {
                    targets.append((row.unit, row.folder[index].value))
                } else if request.button == .keep {
                    targets.append((row.unit, localPayload(row.unit)))
                } else {
                    targets.append((row.unit, row.folder[0].value))
                }
            }
            for target in targets {
                // Exactly the dots the sheet showed, and no others.
                let shown = Set(question.shown[target.unit] ?? [])
                let local = SyncProjection.localValue(target.unit, in: snapshot.values, table: table)
                let isUnchanged = SyncCapture.matches(target.payload, local: local, key: target.unit, table: table)
                let digest = isUnchanged ? (local?.digest ?? .unset) : target.payload.digest
                guard SyncCapture.mint(target.unit, payload: target.payload, digest: digest, state: &state, environment: environment, superseding: shown) else {
                    continue
                }
                write.wrote = true
                if !isUnchanged {
                    write.applies[target.unit] = target.payload
                }
            }
        }
        if !write.applies.isEmpty {
            let after = snapshot.applying(write.applies, table: table)
            for unit in write.applies.keys.sorted() {
                state.baseline[unit] = SyncProjection.localValue(unit, in: after.values, table: table)?.digest ?? .unset
            }
            state.session.snapshot = after
        }
        return write
    }
}
