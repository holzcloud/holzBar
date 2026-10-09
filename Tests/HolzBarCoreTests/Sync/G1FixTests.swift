//
//  G1FixTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The faults that the exploration of gate G1 (plan 28-13) found in the real engine. Each test pins one of them at the level of
/// the fault, with the smallest state that shows it; the traces that found them are in `G1FoundTests`.
@Suite("SyncG1Fixes")
struct G1FixTests {
    private typealias Fixtures = SyncFixtures

    private let table = SyncUnitTable.version1(normalizers: .canonical)
    private let fresh = SyncFreshIdentity(mac: SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!, nonce: "fresh-nonce")
    private let macA = Fixtures.macA
    private let macB = Fixtures.macB
    private let macC = Fixtures.macC
    private let bundleA = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: "com.a")
    private let bundleB = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: "com.b")

    private func environment(_ generation: SyncGeneration = .g27) -> SyncEnvironment {
        Fixtures.environment(generation: generation, freshIdentity: fresh, table: table)
    }

    private func layout27State(_ registers: [SyncUnitKey: [SyncEntry]], local: [SyncUnitKey: SyncValue]) -> SyncState {
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: true)
        state.replica = Fixtures.replica(registers)
        state.session.snapshot = SyncSnapshot(values: local)
        state.session.ownFile = .absent
        state.session.isTrusted = true
        return state
    }

    private func applied(_ step: SyncStep) -> [SyncUnitKey: SyncPayload] {
        for effect in step.effects {
            if case .applyUnits(let changes) = effect {
                return changes
            }
        }
        return [:]
    }

    // MARK: Answers

    @Test("A conflict whose own entry the settings no longer hold is a choice among the values, and the answer takes the one chosen")
    func restoredSettingsAskWhichValueToTake() throws {
        // Preferences that went back leave this Mac's own entry in the replica and nothing in the settings: a row that named the
        // entry as this Mac's value could not be answered, because an answer replaces only a value that is still the one it showed,
        // and the sheet stayed for ever.
        let mine = Fixtures.entry(macA, 4, .string("mine"))
        let theirs = Fixtures.entry(macB, 5, .string("theirs"))
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [mine, theirs]])
        state.counter = 4
        state.publishedCounter = 4
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([:])
        let environment = Fixtures.environment()
        let question = try #require(SyncEngine.question(for: state, scope: .mine, environment: environment))
        let row = try #require(question.rows.first)
        #expect(row.style == .multi)
        #expect(row.local == nil)
        let index = try #require(row.folder.firstIndex { $0.value == .value(.string("theirs")) })
        let request = SyncAnswerRequest(button: .useChosen, choices: [Fixtures.s1: index], question: question)
        let step = SyncEngine.handle(.command(.answer(request)), state: state, environment: environment)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.count == 1)
        #expect(live.first?.payload == .value(.string("theirs")))
        #expect(live.first?.dot.mac == macA)
        #expect(applied(step)[Fixtures.s1] == .value(.string("theirs")))
    }

    @Test("An answer at a join is the user's last word about a unit: a change of it that waited for the join does not come after it")
    func joinAnswerDropsTheQueuedIntentsOfTheUnitsItWrites() throws {
        let theirs = Fixtures.entry(macB, 5, .string("theirs"))
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: false)
        var pending = SyncPendingJoin(
            replica: Fixtures.replica([Fixtures.s1: [theirs]]),
            shown: [Fixtures.s1: [theirs.dot]],
            isFounding: false,
            folderIdentity: "F1"
        )
        pending.phase = .asking
        state.pendingJoin = pending
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine"), Fixtures.s2: .string("other")])
        state.session.ownFile = .absent
        // Changes made while the join waited: the one of S1 is older than the answer, the one of S2 is not touched by it.
        let moveOne = SyncUnitIntent(unit: Fixtures.s1, from: .string("old"), to: .value(.string("mine")))
        let moveTwo = SyncUnitIntent(unit: Fixtures.s2, from: .string("old"), to: .value(.string("other")))
        state.queuedIntents = [moveOne, moveTwo]
        let environment = Fixtures.environment()
        let question = try #require(SyncEngine.question(for: state, scope: .mine, environment: environment))
        let request = SyncAnswerRequest(button: .use, choices: [:], question: question)
        let step = SyncEngine.handle(.command(.answer(request)), state: state, environment: environment)
        #expect(step.state.pendingJoin == nil)
        #expect(step.state.queuedIntents.isEmpty)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.count == 1)
        #expect(live.first?.payload == .value(.string("theirs")))
        #expect(step.state.replica.live(Fixtures.s2).contains { $0.payload == .value(.string("other")) })
    }

    // MARK: Joins

    private func askingJoin(local: SyncValue) -> SyncState {
        let theirs = Fixtures.entry(macB, 5, .string("theirs"))
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: false)
        var pending = SyncPendingJoin(
            replica: Fixtures.replica([Fixtures.s1: [theirs]]),
            shown: [Fixtures.s1: [theirs.dot]],
            isFounding: false,
            folderIdentity: "F1"
        )
        pending.phase = .asking
        state.pendingJoin = pending
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: local])
        state.session.ownFile = .absent
        return state
    }

    @Test("A join that asks commits when the user's change leaves nothing to ask: no sheet is left to answer it")
    func askingJoinCommitsWhenNoRowIsLeft() {
        let state = askingJoin(local: .string("mine"))
        #expect(SyncEngine.question(for: state, scope: .mine, environment: Fixtures.environment()) != nil)
        // The user sets the unit to the group's value while the sheet is open: the row is gone.
        let step = SyncEngine.handle(.defaultsChanged(Fixtures.snapshot([Fixtures.s1: .string("theirs")])), state: state, environment: Fixtures.environment())
        #expect(step.state.pendingJoin == nil)
        #expect(step.state.isEnabled)
    }

    @Test("A join that asks reads the folder again at a launch that finds the preferences rolled back")
    func askingJoinOfARolledBackStateStartsAgain() {
        var stored = askingJoin(local: .string("mine"))
        stored.pendingJoin?.wasTrusted = true
        stored.pendingJoin?.isSameGroup = true
        stored.generation = 5
        stored.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(macA, 3, .string("base"))]])
        stored.counter = 3
        stored.publishedCounter = 3
        let salt = Data("salt".utf8)
        let identity = SyncIdentityInput(
            storedID: macA.rawValue,
            storedHash: SettingsSyncDevice.hardwareHash(of: "HARDWARE-A", uid: 501, salt: salt),
            salt: salt,
            hardwareID: "HARDWARE-A",
            uid: 501
        )
        let input = SyncLaunchInput(
            snapshot: Fixtures.snapshot([Fixtures.s1: .string("base")]),
            stored: .state(stored),
            identity: identity,
            defaultsGeneration: 4,
            lastSyncedSeen: nil,
            syncIsOn: false,
            folder: "F1"
        )
        let step = SyncEngine.handle(.launch(input), state: SyncState(mac: macA, nonce: "ignored"), environment: Fixtures.environment(freshIdentity: fresh))
        #expect(step.state.pendingJoin?.phase == .reading)
        #expect(step.state.pendingJoin?.isSameGroup == false)
        #expect(step.state.pendingJoin?.wasTrusted == false)
        #expect(step.effects.contains { if case .readFolder = $0 { true } else { false } })
    }

    @Test("A join keeps what the settings held when it started as the baseline, so a deletion made while it waited is captured")
    func joinCommitFindsTheDeletionMadeWhileItWaited() {
        let theirs = Fixtures.entry(macB, 5, .string("theirs"))
        // The join started with a value of S1 in the settings.
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: false)
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")])
        state.session.ownFile = .absent
        let started = SyncEngine.handle(.command(.turnOn("F1")), state: state, environment: Fixtures.environment())
        #expect(started.state.pendingJoin?.localAtDecision[Fixtures.s1] == SyncValue.string("mine").digest)
        // The user removed the setting before the folder was read, and the join commits: the baseline is the value it started with.
        var committing = started.state
        committing.replica = Fixtures.replica([Fixtures.s1: [theirs]])
        SyncJoin.settleDotless(
            &committing,
            snapshot: Fixtures.snapshot([:]),
            legacy: nil,
            skipping: [],
            decided: started.state.pendingJoin?.localAtDecision ?? [:],
            environment: Fixtures.environment()
        )
        #expect(committing.baseline[Fixtures.s1] == SyncValue.string("mine").digest)
        committing.isEnabled = true
        committing.pendingJoin = nil
        committing.session.isTrusted = true
        let captured = SyncCapture.capture(Fixtures.snapshot([:]), state: committing, environment: Fixtures.environment())
        #expect(captured.replica.live(Fixtures.s1).contains { $0.payload == .deleted && $0.dot.mac == macA })
    }

    @Test("A folder whose file claims this Mac's own entry is this Mac's group, though this Mac never read that file: a deletion made while sync was off is published, not undone")
    func folderThatHoldsTheMacsOwnEntriesIsItsGroup() throws {
        // Mac A published S1, Mac B read it and wrote a file that relays it; A's own file is gone (the folder was emptied and B's file
        // came back, or A's file was deleted). A turned sync off and deleted the setting, then turns sync on in the folder. A has never
        // read B's file, so the file's writer is unknown to A: only what the file says of A's own dot shows that this is A's group.
        let mine = Fixtures.entry(macA, 4, .string("mine"))
        var state = Fixtures.state()
        state.isEnabled = false
        state.replica = Fixtures.replica([Fixtures.s1: [mine]])
        state.applied[Fixtures.s1] = [mine.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("mine").digest
        state.counter = 4
        state.publishedCounter = 4
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([:])
        let other = Fixtures.entry(macB, 5, .string("two"))
        let relay = SyncDeviceFile.Contents(
            unitTable: 1, mac: macB, installation: "nonce-B", written: Fixtures.now,
            replica: Fixtures.replica([Fixtures.s1: [mine], Fixtures.s2: [other]])
        )
        let read = SyncFolderRead(files: [SyncFileOutcome(macID: macB, size: 200, modified: Fixtures.now, state: .contents(relay))])
        let env = Fixtures.environment()
        let started = SyncEngine.handle(.command(.turnOn("F1")), state: state, environment: env)
        let step = SyncEngine.handle(.folderRead(read, purpose: .join), state: started.state, environment: env)
        #expect(step.state.isEnabled)
        #expect(SyncEngine.question(for: step.state, scope: .mine, environment: env) == nil)
        // The deletion is this Mac's entry in the group; the old value is not back, nor waiting to be applied.
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.map(\.payload) == [.deleted])
        #expect(live.first?.dot.mac == macA)
        #expect(step.state.replica.live(Fixtures.s2).map(\.value) == [.string("two")])
        #expect(!applied(step).keys.contains(Fixtures.s1))
        #expect(step.effects.contains { if case .writeOwnFile = $0 { true } else { false } })
    }

    // MARK: Plan and settle

    @Test("A Mac whose applied entry was replaced by another's of the same value is a party to the conflict that value is in")
    func settleAdoptsAnEqualValuedEntryOfAConflict() {
        let one = Fixtures.entry(macC, 5, .string("one"))
        let two = Fixtures.entry(macB, 6, .string("two"))
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [one, two]], extraContext: [macA: 3])
        state.applied[Fixtures.s1] = [SyncDot(mac: macA, n: 3)]
        state.baseline[Fixtures.s1] = SyncValue.string("one").digest
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("one")])
        state.session.isTrusted = true
        state.session.ownFile = .absent
        let environment = Fixtures.environment()
        let snapshot = state.session.snapshot ?? SyncSnapshot()
        let before = SyncPlan.plan(state: state, snapshot: snapshot, environment: environment)
        #expect(before.outcomes[Fixtures.s1] == .conflict(mine: false))
        let settled = SyncCapture.settle(before, snapshot: snapshot, state: state, environment: environment)
        #expect(settled.applied[Fixtures.s1] == [one.dot])
        let after = SyncPlan.plan(state: settled, snapshot: snapshot, environment: environment)
        #expect(after.outcomes[Fixtures.s1] == .conflict(mine: true))
    }

    @Test("Nothing is minted while a join waits: a quit with a changed setting leaves the replica, the counter and the file as they were")
    func nothingIsMintedWhileAJoinWaits() throws {
        // An enabled Mac that moves to another folder is joining it: the join decides against the state as it is, and what the user
        // changes meanwhile is captured once the join is decided (the diff against the baseline loses nothing). A capture before that
        // would mint an entry that the join's own decision (a founding, a fast-forward, a question) does not know of.
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = SyncValue.string("old").digest
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("old")])
        let started = SyncEngine.handle(.command(.changeFolder("F2")), state: state, environment: Fixtures.environment())
        try #require(started.state.pendingJoin != nil)
        let step = SyncEngine.handle(.quit(Fixtures.snapshot([Fixtures.s1: .string("new")])), state: started.state, environment: Fixtures.environment())
        #expect(step.state.replica == started.state.replica)
        #expect(step.state.replica.live(Fixtures.s1).isEmpty)
        #expect(step.state.counter == started.state.counter)
        #expect(step.state.baseline[Fixtures.s1] == SyncValue.string("old").digest)
        #expect(!step.effects.contains { if case .writeOwnFile = $0 { true } else { false } })
        // After the join is decided the change is still there to be captured.
        var decided = step.state
        decided.pendingJoin = nil
        let captured = SyncCapture.capture(Fixtures.snapshot([Fixtures.s1: .string("new")]), state: decided, environment: Fixtures.environment())
        #expect(captured.replica.live(Fixtures.s1).contains { $0.payload == .value(.string("new")) && $0.dot.mac == macA })
    }

    // MARK: Intents

    @Test("A change of the macOS 27 arrangement made while sync is off waits in the state, one change per unit")
    func intentsOfASwitchedOffMacWaitInTheState() throws {
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: false)
        state.session.snapshot = SyncSnapshot(values: [:])
        let removed = SyncUnitIntent(unit: bundleA, from: .integer(1), to: .deleted)
        let moved = SyncUnitIntent(unit: bundleA, from: nil, to: .value(.integer(2)))
        let first = SyncEngine.handle(.intent(.userSet([removed])), state: state, environment: environment())
        #expect(first.state.queuedIntents == [removed])
        let second = SyncEngine.handle(.intent(.userSet([moved])), state: first.state, environment: environment())
        // The first value the unit had and the last the user set.
        #expect(second.state.queuedIntents == [SyncUnitIntent(unit: bundleA, from: .integer(1), to: .value(.integer(2)))])
    }

    @Test("The waiting changes, the baselines of a join and the ceilings of earlier identities survive Sigma")
    func stateKeepsTheWaitingChanges() throws {
        var state = Fixtures.state()
        state.queuedIntents = [
            SyncUnitIntent(unit: bundleA, from: .integer(1), to: .deleted),
            SyncUnitIntent(unit: bundleB, from: nil, to: .value(.integer(2))),
        ]
        state.previousMacIDs = [macB]
        state.previousCeilings = [macB: 77]
        var pending = SyncPendingJoin(replica: .empty, shown: [:], isFounding: false, folderIdentity: "F1")
        pending.phase = .asking
        pending.localAtDecision = [Fixtures.s1: SyncValue.string("mine").digest, Fixtures.s2: .unset]
        state.pendingJoin = pending
        let data = try SyncStateCodec.encode(state)
        guard case .state(let decoded) = SyncStateCodec.decode(data) else {
            Issue.record("the state did not decode")
            return
        }
        #expect(decoded.queuedIntents == state.queuedIntents)
        #expect(decoded.previousCeilings == [macB: 77])
        #expect(decoded.pendingJoin?.localAtDecision == pending.localAtDecision)
    }

    // MARK: Identity

    @Test("An entry of an earlier identity is this Mac's own up to the counter it had reached there, and another installation's above it")
    func earlierIdentityEntriesAreOwnUpToTheCeiling() {
        let state = SyncFixtures.state()
        let left = SyncEngine.reidentifiedForTests(state, newMac: macB, floors: SyncCounterFloors(mirror: 50, highWater: 60))
        #expect(left.previousMacIDs == [macA])
        #expect(left.previousCeilings[macA] == 60)
        #expect(left.isOwn(SyncDot(mac: macA, n: 60)))
        #expect(!left.isOwn(SyncDot(mac: macA, n: 61)))
        #expect(left.isOwn(SyncDot(mac: macB, n: 1_000_000)))
        #expect(!left.isOwn(SyncDot(mac: macC, n: 1)))
    }
}

extension SyncEngine {
    /// The state after the identity moved to `newMac`, as a launch or a merge does it.
    static func reidentifiedForTests(_ state: SyncState, newMac: SyncMacID, floors: SyncCounterFloors) -> SyncState {
        SyncIdentity.reidentified(state, newMac: newMac, newNonce: "new-nonce", suspect: [], floors: floors)
    }
}
