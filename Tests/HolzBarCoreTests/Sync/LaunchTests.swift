//
//  LaunchTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncLaunch")
struct LaunchTests {
    private typealias Fixtures = SyncFixtures

    private let fresh = SyncFreshIdentity(mac: SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!, nonce: "fresh-nonce")
    private let salt = Data("salt".utf8)
    private let hardware = "HARDWARE-A"
    private let folder: SyncFolderIdentity = "F1"

    // MARK: Builders

    private func environment() -> SyncEnvironment {
        Fixtures.environment(freshIdentity: fresh)
    }

    /// The identity of Mac A, as the defaults hold it when nothing changed.
    private func identity(storedID: String? = Fixtures.macA.rawValue, hardwareID: String? = nil, uid: UInt32 = 501) -> SyncIdentityInput {
        let hardware = hardwareID ?? self.hardware
        return SyncIdentityInput(
            storedID: storedID,
            storedHash: SettingsSyncDevice.hardwareHash(of: self.hardware, uid: 501, salt: salt),
            salt: salt,
            hardwareID: hardware,
            uid: uid
        )
    }

    /// A trusted state of Mac A: it belongs to a group, and its generation is `generation`.
    private func stored(generation: UInt64 = 5, seen: Date? = nil) -> SyncState {
        var state = Fixtures.state(baseline: [Fixtures.s1: SyncValue.string("base").digest, Fixtures.s2: .unset])
        state.generation = generation
        state.legacy.lastSyncedSeen = seen
        let entry = Fixtures.entry(Fixtures.macA, 3, .string("base"))
        state.replica = Fixtures.replica([Fixtures.s1: [entry]])
        state.applied[Fixtures.s1] = [entry.dot]
        state.counter = 3
        state.publishedCounter = 3
        return state
    }

    private func input(
        _ state: SyncState?,
        values: [SyncUnitKey: SyncValue] = [Fixtures.s1: .string("base")],
        generation: UInt64? = 5,
        seen: Date? = nil,
        on: Bool = true,
        identity: SyncIdentityInput? = nil,
        pending: Bool = false
    ) -> SyncLaunchInput {
        SyncLaunchInput(
            snapshot: Fixtures.snapshot(values),
            stored: state.map { .state($0) } ?? .unreadable,
            identity: identity ?? self.identity(),
            defaultsGeneration: generation,
            lastSyncedSeen: seen,
            syncIsOn: on,
            folder: on || pending ? folder : nil
        )
    }

    private func launch(_ input: SyncLaunchInput) -> SyncStep {
        SyncEngine.handle(.launch(input), state: SyncState(mac: Fixtures.macA, nonce: "ignored"), environment: environment())
    }

    /// Nothing but the local persist: no folder access, no apply, no write.
    private func onlyPersists(_ step: SyncStep) -> Bool {
        step.effects.allSatisfy { if case .persist = $0 { true } else { false } }
    }

    private func writes(_ step: SyncStep) -> Bool {
        step.effects.contains { if case .writeOwnFile = $0 { true } else { false } }
    }

    private func applies(_ step: SyncStep) -> [SyncUnitKey: SyncPayload] {
        for effect in step.effects {
            if case .applyUnits(let changes) = effect {
                return changes
            }
        }
        return [:]
    }

    private func readPurpose(_ step: SyncStep) -> SyncReadPurpose? {
        for effect in step.effects {
            if case .readFolder(let request) = effect {
                return request.purpose
            }
        }
        return nil
    }

    private func identityEffect(_ step: SyncStep) -> (SyncMacID, String?)? {
        for effect in step.effects {
            if case .storeIdentity(let mac, let legacy) = effect {
                return (mac, legacy)
            }
        }
        return nil
    }

    // MARK: Off

    @Test("A launch with sync off keeps the state and does nothing else")
    func syncOffKeepsTheState() {
        let state = stored()
        let step = launch(input(state, on: false))
        #expect(step.state.replica == state.replica)
        #expect(step.state.baseline == state.baseline)
        #expect(!step.state.isEnabled)
        #expect(step.state.launchCount == state.launchCount)
        #expect(onlyPersists(step))
        // Without any state and sync off there is a state to turn on from, and nothing was written.
        let blank = launch(input(nil, on: false))
        #expect(blank.state.mac == Fixtures.macA)
        #expect(!blank.state.isEnabled)
        #expect(readPurpose(blank) == nil)
    }

    // MARK: A trusted state

    @Test("A trusted state captures, reads the folder with a budget of one second, applies waiting fast-forwards and writes nothing")
    func trustedLaunchSequence() {
        var state = stored()
        // A waiting entry of another Mac for S2 and a change made while the app was quit.
        let waiting = Fixtures.entry(Fixtures.macB, 5, .string("waiting"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [waiting]]) { $0 + $1 })
        let step = launch(input(state, values: [Fixtures.s1: .string("changed")]))
        #expect(step.state.isEnabled)
        #expect(step.state.launchCount == 1)
        #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("changed")])
        #expect(applies(step) == [Fixtures.s2: .value(.string("waiting"))])
        #expect(!writes(step))
        #expect(readPurpose(step) == .launch(budget: 1))
        // The persist comes before the read, and applies before the persist.
        let names = step.effects.map { effect -> String in
            switch effect {
            case .applyUnits: "apply"
            case .persist: "persist"
            case .readFolder: "read"
            case .schedule: "schedule"
            default: "other"
            }
        }
        #expect(names == ["apply", "persist", "read", "schedule"])
        #expect(step.state.session.isTrusted)
    }

    @Test("A waiting fast-forward applies from the replica alone while the folder is unreachable")
    func fastForwardsApplyWithoutTheFolder() {
        var state = stored()
        let waiting = Fixtures.entry(Fixtures.macB, 5, .string("waiting"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [waiting]]) { $0 + $1 })
        let step = launch(input(state))
        #expect(applies(step) == [Fixtures.s2: .value(.string("waiting"))])
        let away = SyncEngine.handle(.folderRead(SyncFolderRead(availability: .unavailable), purpose: .launch(budget: 1)), state: step.state, environment: environment())
        #expect(!writes(away))
        #expect(applies(away).isEmpty)
        #expect(away.state.replica == step.state.replica)
        #expect(away.state.session.availability == .unavailable)
    }

    @Test("A value that arrives in time at launch is applied at launch, and a later check only shows the Restart hint")
    func launchReadApplies() {
        let state = stored()
        let theirs = Fixtures.entry(Fixtures.macB, 5, .string("theirs"))
        let file = SyncFileOutcome(macID: Fixtures.macB, size: 100, modified: Fixtures.now, state: .contents(
            SyncDeviceFile.Contents(unitTable: 1, mac: Fixtures.macB, installation: "nonce-B", written: Fixtures.now, replica: Fixtures.replica([Fixtures.s2: [theirs]]))
        ))
        let started = launch(input(state))
        let read = SyncFolderRead(files: [file])
        let atLaunch = SyncEngine.handle(.folderRead(read, purpose: .launch(budget: 1)), state: started.state, environment: environment())
        #expect(applies(atLaunch) == [Fixtures.s2: .value(.string("theirs"))])
        let later = SyncEngine.handle(.folderRead(read, purpose: .check), state: started.state, environment: environment())
        #expect(applies(later).isEmpty)
        #expect(SyncEngine.view(of: later.state, environment: environment()).hint == .restart)
    }

    @Test("A crash between applying and persisting re-applies idempotently at the next launch and mints nothing")
    func crashBetweenApplyAndPersist() {
        var state = stored()
        let waiting = Fixtures.entry(Fixtures.macB, 5, .string("waiting"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [waiting]]) { $0 + $1 })
        let first = launch(input(state))
        #expect(applies(first) == [Fixtures.s2: .value(.string("waiting"))])
        // The defaults took the value, Sigma on disk is still the old one.
        let second = launch(input(state, values: [Fixtures.s1: .string("base"), Fixtures.s2: .string("waiting")]))
        #expect(second.state.replica.live(Fixtures.s2) == [waiting])
        #expect(second.state.counter == state.counter)
        #expect(applies(second).isEmpty)
        #expect(second.state.applied[Fixtures.s2] == [waiting.dot])
    }

    @Test("A defaults write made while the app was quit is captured before anything is applied, so it conflicts with a waiting entry")
    func writeWhileQuitIsCapturedFirst() {
        var state = stored()
        let waiting = Fixtures.entry(Fixtures.macB, 5, .string("theirs"))
        state.replica = Fixtures.replica([Fixtures.s1: state.replica.live(Fixtures.s1) + [waiting]].merging([:]) { $0 + $1 })
        // S1 holds A's own applied entry and B's entry, which has not been applied; the user wrote a value.
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 3, .string("base")), waiting]])
        let step = launch(input(state, values: [Fixtures.s1: .string("written")]))
        #expect(applies(step).isEmpty)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.map(\.value).contains(.string("written")))
        #expect(live.contains(waiting))
        let plan = SyncPlan.plan(state: step.state, snapshot: Fixtures.snapshot([Fixtures.s1: .string("written")]), environment: environment())
        #expect(plan.outcomes[Fixtures.s1] == .conflict(mine: true))
    }

    // MARK: Trust

    @Test("Preferences rolled back (a lower defaults generation) join dot-less and mint nothing")
    func generationLowerJoins() {
        let state = stored(generation: 9)
        let step = launch(input(state, values: [Fixtures.s1: .string("older")], generation: 4))
        #expect(step.state.pendingJoin?.phase == .reading)
        #expect(step.state.pendingJoin?.wasTrusted == false)
        #expect(!step.state.session.isTrusted)
        #expect(step.state.replica == state.replica)
        #expect(step.state.counter == state.counter)
        #expect(readPurpose(step) == .join)
        #expect(!writes(step))
        #expect(applies(step).isEmpty)
    }

    @Test("A state that is behind the defaults waits for its own file before it captures")
    func generationHigherWaitsForTheOwnFile() {
        let state = stored(generation: 3)
        let step = launch(input(state, values: [Fixtures.s1: .string("later")], generation: 7))
        #expect(step.state.captureDeferred)
        #expect(!step.state.session.isTrusted)
        #expect(step.state.replica == state.replica)
        #expect(applies(step).isEmpty)
        #expect(step.state.generation > 7, "the next persist is above the defaults")
        // The own file arrives and carries this Mac's later write: joined first, then capture runs.
        let later = Fixtures.entry(Fixtures.macA, 8, .string("later"))
        let own = SyncFileOutcome(macID: Fixtures.macA, size: 100, modified: Fixtures.now, state: .contents(
            SyncDeviceFile.Contents(unitTable: 1, mac: Fixtures.macA, installation: state.nonce, written: Fixtures.now, replica: Fixtures.replica([Fixtures.s1: [later]]))
        ))
        let read = SyncEngine.handle(.folderRead(SyncFolderRead(files: [own]), purpose: .launch(budget: 1)), state: step.state, environment: environment())
        #expect(!read.state.captureDeferred)
        #expect(read.state.session.isTrusted)
        // The value in the defaults equals the own entry: adopted, nothing minted.
        #expect(read.state.replica.live(Fixtures.s1) == [later])
        #expect(read.state.counter >= 8)
        #expect(read.state.applied[Fixtures.s1] == [later.dot])
    }

    @Test("A changed SettingsSyncLastSynced means an older build synced here: a dot-less join")
    func tripwireJoins() {
        let seen = Fixtures.now
        let state = stored(seen: seen)
        let quiet = launch(input(state, seen: seen))
        #expect(quiet.state.pendingJoin == nil)
        let tripped = launch(input(state, seen: seen.addingTimeInterval(60)))
        #expect(tripped.state.pendingJoin?.wasTrusted == false)
        #expect(tripped.state.pendingJoin?.phase == .reading)
        #expect(tripped.state.legacy.lastSyncedSeen == seen, "the engine never rewrites what it saw before the join commits")
        // A key that appears where Sigma saw none trips it as well.
        let appeared = launch(input(stored(seen: nil), seen: seen))
        #expect(appeared.state.pendingJoin != nil)
    }

    @Test("A missing, unreadable or newer state means joining, and is never evidence")
    func noStateJoins() {
        for result in [SyncStateDecodeResult.unreadable, .newerFormat(9)] {
            let launchInput = SyncLaunchInput(
                snapshot: Fixtures.snapshot([Fixtures.s1: .string("mine")]),
                stored: result,
                identity: identity(),
                defaultsGeneration: 5,
                syncIsOn: true,
                folder: folder
            )
            let step = launch(launchInput)
            #expect(step.state.pendingJoin?.phase == .reading)
            #expect(step.state.replica == .empty)
            #expect(step.state.counter == 0)
            #expect(readPurpose(step) == .join)
            #expect(!step.state.session.isTrusted)
            #expect(!writes(step))
        }
    }

    // MARK: Identity

    @Test("A hash that does not match rotates the identity: the new ID is stored, the old one kept as the legacy ID, and Sigma keeps its history")
    func rotatedIdentity() {
        let state = stored()
        let other = SettingsSyncDevice.hardwareHash(of: "OTHER-HARDWARE", uid: 501, salt: salt)
        let rotated = SyncIdentityInput(storedID: Fixtures.macA.rawValue, storedHash: other, salt: salt, hardwareID: hardware, uid: 501)
        let step = launch(input(state, identity: rotated))
        let stored = identityEffect(step)
        #expect(stored?.0 == fresh.mac)
        #expect(stored?.1 == Fixtures.macA.rawValue)
        #expect(step.state.mac == fresh.mac)
        #expect(step.state.nonce == fresh.nonce)
        #expect(step.state.previousMacIDs == [Fixtures.macA])
        #expect(step.state.replica == state.replica)
        #expect(step.state.applied == state.applied)
        #expect(step.state.baseline == state.baseline)
        // The Mac joins again: the same group, since nothing differs from what Sigma captured.
        #expect(step.state.pendingJoin?.wasTrusted == true)
        #expect(step.state.legacy.legacyDeviceID == Fixtures.macA.rawValue)
        // The first effect stores the identity, before anything is persisted.
        if case .storeIdentity = step.effects.first {} else {
            Issue.record("the identity must be stored first")
        }
    }

    @Test("An identity that changed while the settings differ makes the state no evidence")
    func rotatedIdentityWithDifferences() {
        let state = stored()
        let other = SettingsSyncDevice.hardwareHash(of: "OTHER-HARDWARE", uid: 501, salt: salt)
        let rotated = SyncIdentityInput(storedID: Fixtures.macA.rawValue, storedHash: other, salt: salt, hardwareID: hardware, uid: 501)
        let step = launch(input(state, values: [Fixtures.s1: .string("different")], identity: rotated))
        #expect(step.state.pendingJoin?.wasTrusted == false)
        #expect(!step.state.session.isTrusted)
        #expect(step.state.replica.live(Fixtures.s1) == state.replica.live(Fixtures.s1), "nothing is minted")
    }

    @Test("A first run and an ID of an older build store a new ID; an unreadable hardware ID keeps the stored one")
    func identityDecisions() {
        let first = launch(input(nil, identity: SyncIdentityInput(storedID: nil, storedHash: nil, salt: nil, hardwareID: hardware, uid: 501)))
        #expect(identityEffect(first)?.0 == fresh.mac)
        #expect(identityEffect(first)?.1 == nil)
        #expect(first.state.mac == fresh.mac)
        // A β1 ID is no UUID: it rotates once and stays known as the legacy ID.
        let beta = launch(input(nil, identity: SyncIdentityInput(storedID: "DEV-1234", storedHash: nil, salt: nil, hardwareID: hardware, uid: 501)))
        #expect(identityEffect(beta)?.1 == "DEV-1234")
        #expect(beta.state.legacy.legacyDeviceID == "DEV-1234")
        // No hardware ID: the stored identity stays.
        let blind = launch(input(stored(), identity: SyncIdentityInput(storedID: Fixtures.macA.rawValue, storedHash: nil, salt: nil, hardwareID: nil, uid: 501)))
        #expect(identityEffect(blind) == nil)
        #expect(blind.state.mac == Fixtures.macA)
    }

    @Test("Sigma that was re-identified after the defaults were last written keeps its newer identity and the defaults catch up")
    func sigmaIsNewerThanTheDefaults() {
        var state = stored()
        state.mac = fresh.mac
        state.previousMacIDs = [Fixtures.macA]
        let step = launch(input(state, identity: identity(storedID: Fixtures.macA.rawValue)))
        #expect(step.state.mac == fresh.mac)
        #expect(identityEffect(step)?.0 == fresh.mac)
    }

    // MARK: Turn Off and Turn On

    @Test("Turn Off keeps the state, stops all folder access and hides the hint; Turn On with a trusted state asks only about units changed on both sides")
    func turnOffAndOn() throws {
        var state = stored()
        let waiting = Fixtures.entry(Fixtures.macB, 5, .string("waiting"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [waiting]]) { $0 + $1 })
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("base")])
        state.session.isTrusted = true
        #expect(SyncEngine.view(of: state, environment: environment()).hint == .restart)
        let off = SyncEngine.handle(.command(.turnOff), state: state, environment: environment())
        #expect(!off.state.isEnabled)
        #expect(off.state.replica == state.replica)
        #expect(off.effects.contains { if case .forgetFolder = $0 { true } else { false } })
        #expect(off.effects.contains { if case .cancelTimer(.periodic) = $0 { true } else { false } })
        #expect(SyncEngine.view(of: off.state, environment: environment()) == SyncView(hint: nil, lines: []))
        // Timers and reads are ignored while it is off.
        let ignored = SyncEngine.handle(.timer(.periodic), state: off.state, environment: environment())
        #expect(ignored.effects.isEmpty)
        // Relaunched with sync off nothing happens; Turn On resumes with a join of the same group.
        let relaunched = launch(input(off.state, generation: off.state.generation, on: false))
        #expect(onlyPersists(relaunched))
        var on = relaunched.state
        on.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("changed while off")])
        let started = SyncEngine.handle(.command(.turnOn(folder)), state: on, environment: environment())
        #expect(started.state.replica.live(Fixtures.s1).map(\.value) == [.string("changed while off")], "capture ran once")
        #expect(started.state.pendingJoin?.wasTrusted == true)
        #expect(readPurpose(started) == .join)
    }

    @Test("The launch count rises only with sync on, so Later returns at the next launch")
    func launchCountAndLater() {
        var state = stored()
        state.launchCount = 4
        state.laterLaunch = 4
        let off = launch(input(state, on: false))
        #expect(off.state.launchCount == 4)
        let on = launch(input(state))
        #expect(on.state.launchCount == 5)
        #expect(on.state.laterLaunch == 4)
    }

    // MARK: Codec

    @Test("A state with the fields of this plan round-trips, and a state written without them decodes")
    func codecRoundTrip() throws {
        var state = stored()
        state.captureDeferred = true
        var pending = SyncPendingJoin(replica: .empty, shown: [Fixtures.s1: [SyncDot(mac: Fixtures.macB, n: 2)]], isFounding: true, folderIdentity: "F2")
        pending.phase = .asking
        pending.isChange = true
        pending.isSameGroup = true
        pending.wasTrusted = true
        pending.legacy = SyncPendingLegacy(units: [Fixtures.s1: .string("legacy")], modified: Fixtures.now, digest: SyncValue.string("d").digest)
        state.pendingJoin = pending
        let encoded = try SyncStateCodec.encode(state)
        guard case .state(let decoded) = SyncStateCodec.decode(encoded) else {
            Issue.record("the state must decode")
            return
        }
        #expect(decoded.captureDeferred)
        #expect(decoded.pendingJoin == pending)
        // Without the fields: a pending join of the first format is a question that waits.
        var root = try #require(PropertyListSerialization.propertyList(from: encoded, options: [], format: nil) as? [String: Any])
        root["captureDeferred"] = nil
        var join = try #require(root["pendingJoin"] as? [String: Any])
        for key in ["phase", "isChange", "isSameGroup", "wasTrusted", "legacy"] {
            join[key] = nil
        }
        root["pendingJoin"] = join
        let old = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        guard case .state(let legacy) = SyncStateCodec.decode(old) else {
            Issue.record("a state without the new fields must decode")
            return
        }
        #expect(!legacy.captureDeferred)
        #expect(legacy.pendingJoin?.phase == .asking)
        #expect(legacy.pendingJoin?.legacy == nil)
        #expect(legacy.pendingJoin?.wasTrusted == false)
    }
}
