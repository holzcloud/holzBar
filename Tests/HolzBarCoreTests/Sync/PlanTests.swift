//
//  PlanTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncPlan")
struct PlanTests {
    private typealias Fixtures = SyncFixtures

    private func plan(_ state: SyncState, _ values: [SyncUnitKey: SyncValue] = [:], aliased: Set<SyncUnitKey> = [], environment: SyncEnvironment? = nil) -> SyncPlan {
        SyncPlan.plan(state: state, snapshot: Fixtures.snapshot(values, aliased: aliased), environment: environment ?? Fixtures.environment())
    }

    /// A state of Mac A whose replica holds `entries` of `key`, none of them applied.
    private func holding(_ entries: [SyncEntry], key: SyncUnitKey = Fixtures.s1) -> SyncState {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([key: entries])
        return state
    }

    @Test("One live value equal to the local value is equal")
    func equalValue() {
        let state = holding([Fixtures.entry(Fixtures.macB, 5, .string("v"))])
        let result = plan(state, [Fixtures.s1: .string("v")])
        #expect(result.outcomes[Fixtures.s1] == .equal)
        #expect(result.hint == nil)
        let settled = SyncCapture.settle(result, snapshot: Fixtures.snapshot([Fixtures.s1: .string("v")]), state: state, environment: Fixtures.environment())
        #expect(settled.applied[Fixtures.s1] == [SyncDot(mac: Fixtures.macB, n: 5)])
        #expect(settled.baseline[Fixtures.s1] == SyncValue.string("v").digest)
    }

    @Test("One live value that differs is a fast-forward and the hint is Restart")
    func fastForward() {
        let state = holding([Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .fastForward)
        #expect(result.fastForwardPayloads[Fixtures.s1] == .value(.string("theirs")))
        #expect(result.hint == .restart)
    }

    @Test("A user edit that the capture has not minted yet is no change of another Mac: nothing waits and no hint shows")
    func pendingLocalChange() {
        // The only live entry is this Mac's own, and the local value moved on from what was captured.
        var state = holding([Fixtures.entry(Fixtures.macA, 5, .string("captured"))])
        state.baseline[Fixtures.s1] = SyncValue.string("captured").digest
        let result = plan(state, [Fixtures.s1: .string("edited")])
        #expect(result.outcomes[Fixtures.s1] == .pendingLocal)
        #expect(result.fastForwards.isEmpty)
        #expect(result.hint == nil)
        // Another Mac's entry is a fast-forward as before, and so is an own entry when the local value is the captured one.
        var other = holding([Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        other.baseline[Fixtures.s1] = SyncValue.string("captured").digest
        #expect(plan(other, [Fixtures.s1: .string("edited")]).outcomes[Fixtures.s1] == .fastForward)
        #expect(plan(state, [Fixtures.s1: .string("captured")]).outcomes[Fixtures.s1] == .equal)
        // Nothing settles a pending change: its capture still finds the edit.
        let settled = SyncCapture.settle(result, snapshot: Fixtures.snapshot([Fixtures.s1: .string("edited")]), state: state, environment: Fixtures.environment())
        #expect(settled.baseline[Fixtures.s1] == SyncValue.string("captured").digest)
    }

    @Test("A deletion differs from a present value and equals an absent one")
    func deletion() {
        let state = holding([Fixtures.entry(Fixtures.macB, 5, nil)])
        #expect(plan(state, [Fixtures.s1: .string("mine")]).outcomes[Fixtures.s1] == .fastForward)
        #expect(plan(state).outcomes[Fixtures.s1] == .equal)
    }

    @Test("A value that was there before sync and differs from the group is a pre row, and the hint is Choose")
    func preRow() {
        var state = holding([Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        state.localOrigin[Fixtures.s1] = .preexisting
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .preRow)
        #expect(result.hint == .choose)
        #expect(result.questionRows == 1)
    }

    @Test("A pre value with nothing in the group is published as this Mac's entry")
    func preexistingValuePublishedWhereGroupHasNone() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = nil
        let snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")])
        let captured = SyncCapture.capture(snapshot, state: state, environment: Fixtures.environment())
        let result = SyncPlan.plan(state: captured, snapshot: snapshot, environment: Fixtures.environment())
        #expect(result.outcomes[Fixtures.s1] == .publishPreexisting)
        let settled = SyncCapture.settle(result, snapshot: snapshot, state: captured, environment: Fixtures.environment())
        #expect(settled.replica.live(Fixtures.s1).map(\.payload) == [.value(.string("mine"))])
        #expect(settled.localOrigin[Fixtures.s1] == nil)
        #expect(settled.applied[Fixtures.s1]?.count == 1)
    }

    @Test("A local-only unit is protected: nothing replaces it")
    func protectedLocalOnly() {
        var state = holding([Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        state.localOnly[Fixtures.s1] = .oversize
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .protectedLocalOnly)
        #expect(result.fastForwards.isEmpty)
        #expect(result.hint == nil)
    }

    @Test("A value this build cannot use is not applicable and adds the unusable-value line")
    func notApplicable() {
        let state = holding([Fixtures.entry(Fixtures.macB, 5, .string("bad"))])
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .notApplicable)
        #expect(result.hasUnusableValue)
        #expect(result.hint == nil)
        #expect(SyncEngine.view(of: stateWithSnapshot(state, [Fixtures.s1: .string("mine")]), environment: Fixtures.environment()).lines.contains(.unusableValue))
        // An oversize value is not applicable either.
        let big = holding([Fixtures.entry(Fixtures.macB, 6, .string(String(repeating: "x", count: 64)))], key: Fixtures.small)
        #expect(plan(big).outcomes[Fixtures.small] == .notApplicable)
    }

    private func stateWithSnapshot(_ state: SyncState, _ values: [SyncUnitKey: SyncValue]) -> SyncState {
        var state = state
        state.session.snapshot = Fixtures.snapshot(values)
        return state
    }

    @Test("Two live values are this Mac's question when this Mac holds one of them")
    func conflictIsMineWhenIHoldAnEntry() {
        let state = holding([Fixtures.entry(Fixtures.macA, 4, .string("mine")), Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .conflict(mine: true))
        #expect(result.hint == .choose)
        #expect(result.bystanderRows == 0)
    }

    @Test("An earlier identity of this Mac counts as this Mac's")
    func previousIdentityCounts() {
        let previous = SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        var state = holding([Fixtures.entry(previous, 4, .string("mine")), Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        #expect(plan(state).outcomes[Fixtures.s1] == .conflict(mine: false))
        state.previousMacIDs = [previous]
        #expect(plan(state).outcomes[Fixtures.s1] == .conflict(mine: true))
    }

    @Test("A conflict between other Macs gives no hint, only the bystander line")
    func bystanderConflict() {
        let state = holding([Fixtures.entry(Fixtures.macB, 4, .string("one")), Fixtures.entry(Fixtures.macC, 5, .string("two"))])
        let result = plan(state, [Fixtures.s1: .string("mine")])
        #expect(result.outcomes[Fixtures.s1] == .conflict(mine: false))
        #expect(result.hint == nil)
        #expect(result.bystanderRows == 1)
        let view = SyncEngine.view(of: stateWithSnapshot(state, [Fixtures.s1: .string("mine")]), environment: Fixtures.environment())
        #expect(view.hint == nil)
        #expect(view.lines == [.bystander(rows: 1)])
    }

    @Test("The hint is Choose before Restart and nil without either")
    func hintOrder() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([
            Fixtures.s1: [Fixtures.entry(Fixtures.macB, 4, .string("ff"))],
            Fixtures.s2: [Fixtures.entry(Fixtures.macA, 3, .string("a")), Fixtures.entry(Fixtures.macB, 5, .string("b"))],
        ])
        let both = plan(state, [Fixtures.s1: .string("old"), Fixtures.s2: .string("a")])
        #expect(both.hint == .choose)
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macB, 4, .string("ff"))]])
        #expect(plan(state, [Fixtures.s1: .string("old")]).hint == .restart)
        #expect(plan(Fixtures.state()).hint == nil)
    }

    @Test("An aliased unit has the outcome aliased and is never applied")
    func aliasedUnit() {
        let item = Fixtures.item("ns:Title")
        let state = holding([Fixtures.entry(Fixtures.macB, 5, .string("icon"))], key: item)
        let result = plan(state, aliased: [item])
        #expect(result.outcomes[item] == .aliased)
        #expect(result.fastForwards.isEmpty)
    }

    @Test("A unit only macOS 27 authors is relayed on macOS 26, and unknown units have no outcome")
    func unitsOutsideThisMacHaveNoOutcome() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([
            Fixtures.only27: [Fixtures.entry(Fixtures.macB, 5, .string("v"))],
            .whole("FromTheFuture"): [Fixtures.entry(Fixtures.macB, 6, .string("v"))],
        ])
        let on26 = plan(state, environment: Fixtures.environment(generation: .g26))
        #expect(on26.outcomes == [Fixtures.only27: .relayOnly])
        #expect(on26.hint == nil)
        let on27 = plan(state)
        #expect(on27.outcomes[Fixtures.only27] == .fastForward)
        #expect(on27.outcomes[.whole("FromTheFuture")] == nil)
    }

    // MARK: Clash check

    private let hotkeys = Defaults.Key.hotkeys.rawValue

    private func hotkey(_ action: String) -> SyncUnitKey {
        .split(family: hotkeys, item: action)
    }

    private func combination(_ key: Int, _ modifiers: Int) -> SyncValue {
        .data(HotkeyStorage.encode(key: key, modifiers: modifiers))
    }

    private var hotkeyTable: SyncUnitTable { SyncUnitTable.version1(normalizers: .canonical) }

    @Test("Fast-forwarding a hotkey onto a combination another hotkey holds is one clash row that is never applied")
    func hotkeyClash() {
        let search = hotkey("SearchMenuBarItems")
        let toggle = hotkey("ToggleHiddenSection")
        var state = SyncFixtures.state(baseline: [toggle: combination(4, 8).digest])
        state.replica = SyncFixtures.replica([search: [SyncFixtures.entry(SyncFixtures.macB, 5, combination(4, 8))]])
        let result = plan(
            state,
            [toggle: combination(4, 8)],
            environment: SyncFixtures.environment(table: hotkeyTable)
        )
        #expect(result.outcomes[search] == .clash)
        #expect(result.clashes == [SyncClash(units: [search, toggle].sorted())])
        #expect(result.fastForwards.isEmpty)
        #expect(result.fastForwardPayloads.isEmpty)
        #expect(result.hint == .choose)
        #expect(result.questionRows == 1)
    }

    @Test("Without a shared combination the hotkey fast-forwards stay")
    func hotkeysWithoutClash() {
        let search = hotkey("SearchMenuBarItems")
        let toggle = hotkey("ToggleHiddenSection")
        var state = SyncFixtures.state(baseline: [toggle: combination(4, 8).digest])
        state.replica = SyncFixtures.replica([search: [SyncFixtures.entry(SyncFixtures.macB, 5, combination(5, 8))]])
        let result = plan(state, [toggle: combination(4, 8)], environment: SyncFixtures.environment(table: hotkeyTable))
        #expect(result.outcomes[search] == .fastForward)
        #expect(result.clashes.isEmpty)
        #expect(result.hint == .restart)
    }

    @Test("A deleted or cleared hotkey frees its combination")
    func clearedHotkeyDoesNotClash() {
        let search = hotkey("SearchMenuBarItems")
        let toggle = hotkey("ToggleHiddenSection")
        var state = SyncFixtures.state()
        state.replica = SyncFixtures.replica([
            search: [SyncFixtures.entry(SyncFixtures.macB, 5, combination(4, 8))],
            toggle: [SyncFixtures.entry(SyncFixtures.macB, 6, nil)],
        ])
        let result = plan(
            state,
            [toggle: combination(4, 8)],
            environment: SyncFixtures.environment(table: hotkeyTable)
        )
        #expect(result.clashes.isEmpty)
        #expect(result.outcomes[search] == .fastForward)
        #expect(result.outcomes[toggle] == .fastForward)
    }

    // MARK: Persistence

    @Test("An entry waiting for Restart survives a relaunch, a deleted file and later arrivals")
    func waitingEntrySurvives() throws {
        let state = holding([Fixtures.entry(Fixtures.macB, 5, .string("theirs"))])
        let values: [SyncUnitKey: SyncValue] = [Fixtures.s1: .string("mine")]
        let before = plan(state, values)
        #expect(before.outcomes[Fixtures.s1] == .fastForward)

        // A relaunch decodes Sigma again.
        let data = try SyncStateCodec.encode(state)
        guard case .state(let relaunched) = SyncStateCodec.decode(data) else {
            Issue.record("Sigma did not decode")
            return
        }
        #expect(plan(relaunched, values).outcomes == before.outcomes)

        // The file that carried the entry is deleted: an empty read changes nothing.
        let afterDelete = SyncMerge.merge(SyncFolderRead(), into: relaunched, environment: Fixtures.environment()).state
        #expect(afterDelete.replica == state.replica)
        #expect(plan(afterDelete, values).outcomes == before.outcomes)

        // A later arrival of another unit does not disturb it.
        var other = Fixtures.state(Fixtures.macC)
        other.replica = Fixtures.replica([Fixtures.s2: [Fixtures.entry(Fixtures.macC, 9, .string("other"))]])
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: Fixtures.macC, installation: "x", written: Fixtures.now, replica: other.replica)
        let read = SyncFolderRead(files: [SyncFileOutcome(macID: Fixtures.macC, state: .contents(contents))])
        let merged = SyncMerge.merge(read, into: afterDelete, environment: Fixtures.environment()).state
        let later = plan(merged, values)
        #expect(later.outcomes[Fixtures.s1] == .fastForward)
        #expect(later.outcomes[Fixtures.s2] == .fastForward)
    }

    // MARK: Status lines

    @Test("The view lists the status lines from the persisted state and the session")
    func statusLines() {
        var state = Fixtures.state()
        state.refusals[Fixtures.macB.rawValue] = SyncRefusalRecord(reason: SyncRefusal.newerFormat(2).code, size: 10, modified: nil, firstSeen: Fixtures.now)
        state.refusals[Fixtures.macC.rawValue] = SyncRefusalRecord(reason: SyncRefusal.tooLarge(2).code, size: 10, modified: nil, firstSeen: Fixtures.now)
        state.session.waitingFiles = 2
        state.session.skippedFiles = 3
        state.localOnly[.whole(SyncUnitTable.holzBarIconUnit)] = .oversize
        state.legacy.lastLegacyChange = Fixtures.now.addingTimeInterval(-10 * 24 * 3600)
        let lines = SyncEngine.view(of: state, environment: Fixtures.environment()).lines
        #expect(lines.contains(.waitingFiles(2)))
        #expect(lines.contains(.newerFormat))
        #expect(lines.contains(.unreadableFile))
        #expect(lines.contains(.olderHolzBar))
        #expect(lines.contains(.oversizeIcon))
        #expect(lines.contains(.skippedFiles(3)))
        // After 30 days the legacy line is gone.
        state.legacy.lastLegacyChange = Fixtures.now.addingTimeInterval(-31 * 24 * 3600)
        #expect(!SyncEngine.view(of: state, environment: Fixtures.environment()).lines.contains(.olderHolzBar))
    }

    @Test("A join that reads shows the joining line, and one that asks shows the join hint")
    func joiningView() {
        var state = Fixtures.state()
        state.pendingJoin = SyncPendingJoin(replica: .empty, shown: [:], isFounding: false, folderIdentity: nil, phase: .reading)
        state.session.waitingFiles = 4
        let reading = SyncEngine.view(of: state, environment: Fixtures.environment())
        #expect(reading.hint == nil)
        #expect(reading.lines.first == .joining(waitingFiles: 4))
        state.pendingJoin?.phase = .asking
        let asking = SyncEngine.view(of: state, environment: Fixtures.environment())
        #expect(asking.hint == .chooseAfterJoin)
        #expect(!asking.lines.contains(.joining(waitingFiles: 4)))
    }
}
