//
//  JoinTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncJoin")
struct JoinTests {
    private typealias Fixtures = SyncFixtures

    private let fresh = SyncFreshIdentity(mac: SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!, nonce: "fresh-nonce")
    private let folder: SyncFolderIdentity = "F1"
    private let realTable = SyncUnitTable.version1(normalizers: .canonical)
    private let hover = SyncUnitKey.whole("ShowOnHover")
    private let click = SyncUnitKey.whole("ShowOnClick")

    // MARK: Builders

    private func environment(table: SyncUnitTable? = nil) -> SyncEnvironment {
        Fixtures.environment(freshIdentity: fresh, table: table ?? Fixtures.table)
    }

    private func contents(_ mac: SyncMacID, _ replica: SyncReplica, installation: String? = nil) -> SyncDeviceFile.Contents {
        SyncDeviceFile.Contents(unitTable: 1, mac: mac, installation: installation ?? "nonce-\(mac.rawValue.prefix(1))", written: Fixtures.now, replica: replica)
    }

    private func file(_ contents: SyncDeviceFile.Contents) -> SyncFileOutcome {
        SyncFileOutcome(macID: contents.mac, size: 200, modified: Fixtures.now, state: .contents(contents))
    }

    /// A Mac that never synced: no group, an untrusted state, sync off, holding `values`.
    private func joiner(_ values: [SyncUnitKey: SyncValue] = [:], mac: SyncMacID = Fixtures.macA) -> SyncState {
        var state = SyncState(mac: mac, nonce: "nonce-\(mac.rawValue.prefix(1))", isEnabled: false)
        state.session.snapshot = Fixtures.snapshot(values)
        state.session.isTrusted = false
        return state
    }

    /// Turn On… and the read that follows.
    private func join(_ state: SyncState, _ read: SyncFolderRead, environment: SyncEnvironment? = nil) -> SyncStep {
        let env = environment ?? self.environment()
        let started = SyncEngine.handle(.command(.turnOn(folder)), state: state, environment: env)
        return SyncEngine.handle(.folderRead(read, purpose: .join), state: started.state, environment: env)
    }

    private func hasWrite(_ step: SyncStep) -> Bool {
        step.effects.contains { if case .writeOwnFile = $0 { true } else { false } }
    }

    private func hasApply(_ step: SyncStep) -> Bool {
        step.effects.contains { if case .applyUnits = $0 { true } else { false } }
    }

    private func committed(_ step: SyncStep) -> Bool {
        step.effects.contains { if case .commitFolder = $0 { true } else { false } }
    }

    private func question(_ step: SyncStep, environment: SyncEnvironment? = nil) -> SyncQuestion? {
        SyncEngine.question(for: step.state, scope: .mine, environment: environment ?? self.environment())
    }

    /// A group of Mac B with `S1 = "b"`.
    private func groupFile(_ value: SyncValue = .string("b"), n: UInt64 = 5) -> (SyncFileOutcome, SyncEntry) {
        let entry = Fixtures.entry(Fixtures.macB, n, value)
        return (file(contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [entry]]))), entry)
    }

    // MARK: Founding

    @Test("An empty Macs folder with a good listing founds the group: this Mac's values become entries and nothing is asked")
    func foundingPublishesAndAsksNothing() {
        let step = join(joiner([Fixtures.s1: .string("mine"), Fixtures.s2: .string("two")]), SyncFolderRead(files: []))
        #expect(committed(step))
        #expect(step.state.pendingJoin == nil)
        #expect(step.state.isEnabled)
        #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("mine")])
        #expect(step.state.replica.live(Fixtures.s2).map(\.value) == [.string("two")])
        #expect(step.state.replica.live(Fixtures.s1).first?.dot.mac == Fixtures.macA)
        #expect(hasWrite(step))
        #expect(!hasApply(step))
        #expect(question(step) == nil)
        // A unit that holds no value has the baseline "unset", so a later value is captured.
        #expect(step.state.baseline[Fixtures.small] == .unset)
    }

    @Test("A listing that failed never founds: the join stays pending and writes nothing")
    func failedListingNeverFounds() {
        for availability in [SyncFolderAvailability.unavailable, .unusable] {
            let step = join(joiner([Fixtures.s1: .string("mine")]), SyncFolderRead(availability: availability, files: []))
            #expect(!committed(step))
            #expect(!hasWrite(step))
            #expect(step.state.pendingJoin?.phase == .reading)
            #expect(!step.state.isEnabled)
        }
    }

    @Test("Files that are dataless or pending never found; the join waits, asks for the download and commits nothing (INV-J1)")
    func waitingFilesNeverFound() throws {
        let dataless = SyncFileOutcome(macID: Fixtures.macB, state: .dataless)
        let pending = SyncFileOutcome(macID: Fixtures.macC, state: .pending)
        let step = join(joiner([Fixtures.s1: .string("mine")]), SyncFolderRead(files: [dataless, pending]))
        #expect(!committed(step))
        #expect(!hasWrite(step))
        #expect(step.state.pendingJoin?.phase == .reading)
        #expect(step.state.session.waitingFiles == 2)
        #expect(step.effects.contains { if case .requestDownload(let macs) = $0 { macs == [Fixtures.macB] } else { false } })
        #expect(step.effects.contains { if case .schedule(.check, _) = $0 { true } else { false } })
        let view = SyncEngine.view(of: step.state, environment: environment())
        #expect(view.lines.contains(.joining(waitingFiles: 2)))
        #expect(view.hint == nil)
        // The files arrive: the join goes on and asks about the one difference.
        let (arrived, _) = groupFile()
        let next = SyncEngine.handle(.folderRead(SyncFolderRead(files: [arrived]), purpose: .join), state: step.state, environment: environment())
        #expect(next.state.pendingJoin?.phase == .asking)
        #expect(!committed(next))
    }

    @Test("A file refused for a lasting reason does not make the join wait; an unreadable one does")
    func refusalsAndWaiting() {
        let lasting = SyncFileOutcome(macID: Fixtures.macB, size: 5 << 20, state: .refused(.tooLarge(5 << 20)))
        let step = join(joiner([Fixtures.s1: .string("mine")]), SyncFolderRead(files: [lasting]))
        #expect(committed(step))
        #expect(step.state.refusals[Fixtures.macB.rawValue]?.reason == SyncRefusal.tooLarge(0).code)
        // Not founding: a device file is listed, so no legacy input counts, and this Mac's value is published.
        #expect(step.state.pendingJoin == nil)
        #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("mine")])
        let unreadable = SyncFileOutcome(macID: Fixtures.macB, state: .refused(.unreadable))
        let waiting = join(joiner([Fixtures.s1: .string("mine")]), SyncFolderRead(files: [unreadable]))
        #expect(!committed(waiting))
        #expect(waiting.state.session.waitingFiles == 1)
    }

    // MARK: The legacy file

    private func legacyFile(_ settings: [String: SyncValue], deviceID: String? = "OLD-1") -> SyncLegacyFile {
        let modified = Fixtures.now.addingTimeInterval(-3600)
        var identity: [String: SyncValue] = [SettingsSyncFile.modifiedKey: .date(modified)]
        identity[SettingsSyncDevice.deviceIDKey] = deviceID.map { .string($0) }
        return SyncLegacyFile(modified: modified, deviceID: deviceID, settings: settings, identityDigest: SyncValue.dictionary(identity).digest)
    }

    @Test("Founding compares a legacy file once: a differing unit is a row that carries the legacy date, and the file is never written")
    func legacyFoundingRow() throws {
        let env = environment(table: realTable)
        let legacy = legacyFile(["ShowOnHover": .bool(true), "ShowOnClick": .bool(false)])
        let state = joiner([hover: .bool(false), click: .bool(false)])
        let step = join(state, SyncFolderRead(files: [], legacy: .file(legacy)), environment: env)
        let asked = try #require(question(step, environment: env))
        #expect(asked.kind == .joining)
        #expect(asked.rows.map(\.unit) == [hover])
        let row = try #require(asked.rows.first)
        #expect(row.folder.map(\.source) == [.legacyFile])
        #expect(row.folder.first?.at == legacy.modified)
        #expect(row.folder.first?.value == .value(.bool(true)))
        #expect(asked.shown[hover] == [])
        #expect(!hasWrite(step))
        // Use takes the legacy value as this Mac's own entry; the equal unit became an entry silently.
        let answered = SyncEngine.handle(.command(.answer(SyncAnswerRequest(button: .use, question: asked))), state: step.state, environment: env)
        #expect(answered.state.replica.live(hover).map(\.value) == [.bool(true)])
        #expect(answered.state.replica.live(click).map(\.value) == [.bool(false)])
        #expect(answered.state.replica.live(hover).allSatisfy { $0.dot.mac == Fixtures.macA })
        #expect(answered.state.legacy.foundingDigest == legacy.identityDigest)
        #expect(committed(answered))
    }

    @Test("A legacy file written by this Mac's own legacy ID, or a folder that holds a device file, gives no founding input")
    func legacyIgnored() {
        let env = environment(table: realTable)
        let legacy = legacyFile(["ShowOnHover": .bool(true)])
        var own = joiner([hover: .bool(false)])
        own.legacy.legacyDeviceID = "OLD-1"
        let ownStep = join(own, SyncFolderRead(files: [], legacy: .file(legacy)), environment: env)
        #expect(question(ownStep, environment: env) == nil)
        #expect(ownStep.state.replica.live(hover).map(\.value) == [.bool(false)])
        // The digest is still recorded, for the status line.
        #expect(ownStep.state.legacy.foundingDigest == legacy.identityDigest)
        let other = file(contents(Fixtures.macB, Fixtures.replica([click: [Fixtures.entry(Fixtures.macB, 3, .bool(true))]])))
        let joined = join(joiner([hover: .bool(false)]), SyncFolderRead(files: [other], legacy: .file(legacy)), environment: env)
        #expect(question(joined, environment: env) == nil)
        #expect(joined.state.replica.live(hover).map(\.value) == [.bool(false)])
    }

    // MARK: The preview table

    @Test("The preview has one result for each row of the table")
    func previewTable() {
        let env = environment()
        let one = Fixtures.entry(Fixtures.macB, 1, .string("a")).payload
        let two = Fixtures.entry(Fixtures.macC, 2, .string("b")).payload
        func preview(_ local: SyncValue?, _ folder: [SyncPayload], legacy: SyncValue? = nil) -> SyncJoinPreview {
            SyncJoin.preview(unit: Fixtures.s1, local: local, folder: folder, legacy: legacy, environment: env)
        }
        #expect(preview(.string("a"), [one]) == .adopt)
        #expect(preview(nil, [one]) == .fastForward)
        #expect(preview(.string("a"), []) == .publish)
        #expect(preview(.string("x"), [one]) == .row)
        #expect(preview(.string("a"), [one, two]) == .adoptSibling)
        #expect(preview(.string("x"), [one, two]) == .multiRow)
        #expect(preview(nil, [one, two]) == .bystander)
        #expect(preview(nil, []) == .nothing)
        // A deletion equals an absent value.
        #expect(preview(nil, [.deleted]) == .adopt)
        // The legacy value counts only where the folder has none.
        #expect(preview(.string("x"), [], legacy: .string("a")) == .row)
        #expect(preview(.string("x"), [one], legacy: .string("a")) == .row)
        #expect(SyncJoin.overall(of: SyncFolderRead(availability: .unavailable), waiting: 0) == .refused)
        #expect(SyncJoin.overall(of: SyncFolderRead(), waiting: 3) == .waiting(files: 3))
        #expect(SyncJoin.overall(of: SyncFolderRead(), waiting: 0) == nil)
    }

    @Test("No user value means the key is absent: a key that holds the default value is asked about, a fresh install adopts silently")
    func absentIsNoValue() throws {
        let (theirs, entry) = groupFile(.string("b"))
        // A value, even one that equals a default, differs from the folder: a row.
        let present = join(joiner([Fixtures.s1: .string("default")]), SyncFolderRead(files: [theirs]))
        let asked = try #require(question(present))
        #expect(asked.rows.map(\.unit) == [Fixtures.s1])
        #expect(asked.shown[Fixtures.s1] == [entry.dot])
        // Nothing stored: the folder's values wait as fast-forwards, nothing is asked, nothing is applied.
        let blank = join(joiner(), SyncFolderRead(files: [theirs]))
        #expect(committed(blank))
        #expect(question(blank) == nil)
        #expect(!hasApply(blank))
        let plan = SyncPlan.plan(state: blank.state, snapshot: blank.state.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[Fixtures.s1] == .fastForward)
        #expect(SyncEngine.view(of: blank.state, environment: environment()).hint == .restart)
        // Equal values are adopted silently.
        let equal = join(joiner([Fixtures.s1: .string("b")]), SyncFolderRead(files: [theirs]))
        #expect(committed(equal))
        #expect(equal.state.applied[Fixtures.s1] == [entry.dot])
        #expect(question(equal) == nil)
        #expect(!hasApply(equal))
    }

    @Test("A value present here and not in the folder is published; equal to one of several adopts that sibling; absent with several is a bystander conflict")
    func severalValues() throws {
        let first = Fixtures.entry(Fixtures.macB, 5, .string("b"))
        let second = Fixtures.entry(Fixtures.macC, 6, .string("c"))
        let theirs = [
            file(contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [first], Fixtures.s2: [first]]))),
            file(contents(Fixtures.macC, Fixtures.replica([Fixtures.s1: [second], Fixtures.s2: [second]]))),
        ]
        // Equal to one of several: adopt that sibling's dots, then an ordinary conflict this Mac takes part in.
        let adopt = join(joiner([Fixtures.s1: .string("b"), Fixtures.small: .string("s")]), SyncFolderRead(files: theirs))
        #expect(committed(adopt))
        #expect(adopt.state.applied[Fixtures.s1] == [first.dot])
        let plan = SyncPlan.plan(state: adopt.state, snapshot: adopt.state.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[Fixtures.s1] == .conflict(mine: true))
        // Present here, none in the folder: published as this Mac's entry.
        #expect(adopt.state.replica.live(Fixtures.small).map(\.value) == [.string("s")])
        // Absent here with several: a conflict between other Macs, with no hint.
        #expect(plan.outcomes[Fixtures.s2] == .conflict(mine: false))
        #expect(plan.hint == .choose)
        // Equal to none of several: one row that lists every value.
        let multi = join(joiner([Fixtures.s1: .string("x")]), SyncFolderRead(files: theirs))
        let row = try #require(question(multi)?.rows.first)
        #expect(row.style == .multi)
        #expect(row.folder.map(\.value) == [first.payload, second.payload])
        let bystander = join(joiner(), SyncFolderRead(files: theirs))
        #expect(question(bystander) == nil)
        let line = SyncEngine.view(of: bystander.state, environment: environment()).lines
        #expect(line.contains(.bystander(rows: 2)))
    }

    // MARK: Groups

    @Test("Same group: capture runs first, so only a unit changed on both sides is a row")
    func sameGroupAsksAboutBothSidedChanges() throws {
        // This Mac (A) was in a group with B, turned sync off, then changed S1 and Small; B changed S1 and S2.
        let base = Fixtures.entry(Fixtures.macB, 3, .string("base"))
        var state = Fixtures.state()
        state.isEnabled = false
        state.replica = Fixtures.replica([Fixtures.s1: [base]])
        state.applied[Fixtures.s1] = [base.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("base").digest
        state.session.isTrusted = true
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine"), Fixtures.small: .string("s")])
        let theirs = Fixtures.entry(Fixtures.macB, 4, .string("theirs"))
        let other = Fixtures.entry(Fixtures.macB, 5, .string("two"))
        let read = SyncFolderRead(files: [file(contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [theirs], Fixtures.s2: [other]])))])
        let step = join(state, read)
        let asked = try #require(question(step))
        #expect(asked.kind == .joining)
        #expect(asked.rows.map(\.unit) == [Fixtures.s1])
        #expect(step.state.pendingJoin?.isSameGroup == true)
        #expect(!committed(step))
        // Cancel keeps sync off, and the capture that ran stays in the state.
        let cancelled = SyncEngine.handle(.command(.answer(SyncAnswerRequest(button: .cancel, question: asked))), state: step.state, environment: environment())
        #expect(cancelled.state.pendingJoin == nil)
        #expect(!cancelled.state.isEnabled)
        #expect(!hasWrite(cancelled))
        // Keep merges: the unit this Mac changed alone and the one B changed alone need no question.
        let kept = SyncEngine.handle(.command(.answer(SyncAnswerRequest(button: .keep, question: asked))), state: step.state, environment: environment())
        #expect(kept.state.isEnabled)
        #expect(kept.state.replica.live(Fixtures.s1).map(\.value) == [.string("mine")])
        #expect(kept.state.replica.live(Fixtures.small).map(\.value) == [.string("s")])
        #expect(kept.state.replica.live(Fixtures.s2).map(\.value) == [.string("two")])
        let plan = SyncPlan.plan(state: kept.state, snapshot: kept.state.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[Fixtures.s2] == .fastForward)
    }

    @Test("Another group joins dot-less, and the old group's entries are dropped at the commit")
    func otherGroupIsDotless() {
        var state = Fixtures.state()
        state.isEnabled = false
        let oldEntry = Fixtures.entry(Fixtures.macC, 9, .string("old"))
        state.replica = Fixtures.replica([Fixtures.s2: [oldEntry]])
        state.applied[Fixtures.s2] = [oldEntry.dot]
        state.session.isTrusted = true
        state.session.snapshot = Fixtures.snapshot([Fixtures.s2: .string("old")])
        let (theirs, entry) = groupFile(.string("b"))
        let step = join(state, SyncFolderRead(files: [theirs]))
        #expect(step.state.pendingJoin?.isSameGroup == false || step.state.pendingJoin == nil)
        #expect(committed(step))
        #expect(step.state.replica.live(Fixtures.s1) == [entry])
        // The old group's entry of another Mac is gone; this Mac's value stays, as its own entry.
        #expect(step.state.replica.live(Fixtures.s2).map(\.dot.mac) == [Fixtures.macA])
        #expect(step.state.replica.live(Fixtures.s2).map(\.value) == [.string("old")])
        #expect(question(step) == nil)
    }

    @Test("Change to an empty folder publishes the state's replica there; Change to another group is dot-less and Cancel keeps the old folder")
    func changeFolder() throws {
        let entry = Fixtures.entry(Fixtures.macA, 4, .string("mine"))
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [entry]])
        state.applied[Fixtures.s1] = [entry.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("mine").digest
        state.publishedCounter = 4
        state.counter = 4
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")])
        let env = environment()
        let started = SyncEngine.handle(.command(.changeFolder("F2")), state: state, environment: env)
        #expect(started.state.pendingJoin?.isChange == true)
        #expect(started.state.isEnabled)
        let empty = SyncEngine.handle(.folderRead(SyncFolderRead(files: []), purpose: .join), state: started.state, environment: env)
        #expect(committed(empty))
        #expect(empty.state.replica == state.replica)
        #expect(hasWrite(empty))
        // Another group: B's folder holds a different value for S1.
        let (theirs, _) = groupFile(.string("b"))
        let other = SyncEngine.handle(.folderRead(SyncFolderRead(files: [theirs]), purpose: .join), state: started.state, environment: env)
        let asked = try #require(question(other))
        #expect(other.state.pendingJoin?.isSameGroup == false)
        #expect(other.state.pendingJoin?.isChange == true)
        let cancelled = SyncEngine.handle(.command(.cancelJoin), state: other.state, environment: env)
        #expect(cancelled.state.isEnabled)
        #expect(cancelled.state.replica == state.replica)
        #expect(cancelled.state.pendingJoin == nil)
        #expect(!hasWrite(cancelled))
        #expect(!cancelled.effects.contains { if case .commitFolder = $0 { true } else { false } })
        #expect(asked.rows.count == 1)
    }

    // MARK: Pending joins

    @Test("The pending join is part of the state: after a relaunch the same rows come back, and a newer arrival leaves the shown dots alone")
    func pendingJoinSurvivesRelaunch() throws {
        let env = environment()
        let (theirs, _) = groupFile(.string("b"))
        let step = join(joiner([Fixtures.s1: .string("x"), Fixtures.s2: .string("y")]), SyncFolderRead(files: [theirs]))
        let asked = try #require(question(step))
        #expect(step.state.pendingJoin?.shown == asked.shown)
        let encoded = try SyncStateCodec.encode(step.state)
        guard case .state(let restored) = SyncStateCodec.decode(encoded) else {
            Issue.record("the state with a pending join must decode")
            return
        }
        var relaunched = restored
        relaunched.session.snapshot = step.state.session.snapshot
        #expect(restored.pendingJoin == step.state.pendingJoin)
        #expect(SyncEngine.question(for: relaunched, scope: .mine, environment: env) == asked)
        // A newer entry arrives while the question is open: it is not merged, and `shown` stays.
        let newer = Fixtures.entry(Fixtures.macC, 8, .string("c"))
        let arrival = file(contents(Fixtures.macC, Fixtures.replica([Fixtures.s1: [newer]])))
        let later = SyncEngine.handle(.folderRead(SyncFolderRead(files: [arrival]), purpose: .check), state: step.state, environment: env)
        #expect(later.state.pendingJoin?.shown == asked.shown)
        #expect(later.state.pendingJoin?.replica == step.state.pendingJoin?.replica)
        #expect(!hasWrite(later))
    }

    @Test("Cancel after Turn On leaves sync off and writes nothing, whether the join reads or asks")
    func cancelAfterTurnOn() throws {
        let env = environment()
        let reading = SyncEngine.handle(.command(.turnOn(folder)), state: joiner([Fixtures.s1: .string("x")]), environment: env)
        #expect(reading.state.pendingJoin?.phase == .reading)
        let cancelled = SyncEngine.handle(.command(.cancelJoin), state: reading.state, environment: env)
        #expect(cancelled.state.pendingJoin == nil)
        #expect(!cancelled.state.isEnabled)
        #expect(cancelled.effects.allSatisfy { if case .persist = $0 { true } else { false } })
        // A read that arrives after the Cancel changes nothing.
        let stale = SyncEngine.handle(.folderRead(SyncFolderRead(files: []), purpose: .join), state: cancelled.state, environment: env)
        #expect(!stale.state.isEnabled)
        #expect(!committed(stale))
        let (theirs, _) = groupFile(.string("b"))
        let asking = join(joiner([Fixtures.s1: .string("x")]), SyncFolderRead(files: [theirs]))
        let asked = try #require(question(asking))
        let answered = SyncEngine.handle(.command(.answer(SyncAnswerRequest(button: .cancel, question: asked))), state: asking.state, environment: env)
        #expect(answered.state.pendingJoin == nil)
        #expect(!answered.state.isEnabled)
        #expect(answered.effects.allSatisfy { if case .persist = $0 { true } else { false } })
    }

    @Test("Nothing is applied or published before the commit, and nothing of a join asking leaves the state")
    func nothingBeforeTheCommit() throws {
        let (theirs, _) = groupFile(.string("b"))
        let step = join(joiner([Fixtures.s1: .string("x")]), SyncFolderRead(files: [theirs]))
        #expect(!hasApply(step))
        #expect(!hasWrite(step))
        #expect(!committed(step))
        // The state's own replica is untouched until the commit.
        #expect(step.state.replica == .empty)
        // Even a timer that fires meanwhile writes nothing.
        let capture = SyncEngine.handle(.timer(.capture), state: step.state, environment: environment())
        #expect(!hasWrite(capture))
        let periodic = SyncEngine.handle(.timer(.periodic), state: step.state, environment: environment())
        #expect(periodic.effects.isEmpty)
    }

    @Test("Two Macs that found at once publish: equal values collapse, different values are an ordinary conflict")
    func twoFoundersAtOnce() throws {
        let env = environment()
        func found(_ mac: SyncMacID, _ value: SyncValue) -> SyncStep {
            join(joiner([Fixtures.s1: value], mac: mac), SyncFolderRead(files: []))
        }
        func exchange(_ one: SyncStep, _ two: SyncStep) -> (SyncState, SyncState) {
            func contents(_ step: SyncStep) -> SyncFileOutcome {
                guard let write = step.effects.compactMap({ effect -> SyncWriteRequest? in
                    if case .writeOwnFile(let request) = effect { request } else { nil }
                }).first else {
                    Issue.record("a founder must write its file")
                    return SyncFileOutcome(macID: nil, state: .pending)
                }
                return file(write.contents)
            }
            let first = SyncEngine.handle(.folderRead(SyncFolderRead(files: [contents(two)]), purpose: .check), state: one.state, environment: env)
            let second = SyncEngine.handle(.folderRead(SyncFolderRead(files: [contents(one)]), purpose: .check), state: two.state, environment: env)
            return (first.state, second.state)
        }
        let equal = exchange(found(Fixtures.macA, .string("same")), found(Fixtures.macB, .string("same")))
        for state in [equal.0, equal.1] {
            #expect(state.replica.distinctValues(Fixtures.s1) == [.value(.string("same"))])
            let plan = SyncPlan.plan(state: state, snapshot: state.session.snapshot ?? SyncSnapshot(), environment: env)
            #expect(plan.outcomes[Fixtures.s1] == .equal)
        }
        let different = exchange(found(Fixtures.macA, .string("a")), found(Fixtures.macB, .string("b")))
        for state in [different.0, different.1] {
            #expect(state.replica.distinctValues(Fixtures.s1).count == 2)
            let plan = SyncPlan.plan(state: state, snapshot: state.session.snapshot ?? SyncSnapshot(), environment: env)
            #expect(plan.outcomes[Fixtures.s1] == .conflict(mine: true))
        }
    }

    @Test("A unit that is new to the table joins on its own: its present value is preexisting, with no join of the folder")
    func newUnitJoinsAlone() {
        var state = Fixtures.state(baseline: [Fixtures.s1: .unset])
        state.session.snapshot = Fixtures.snapshot([Fixtures.s2: .string("new")])
        let step = SyncEngine.handle(.timer(.capture), state: state, environment: environment())
        #expect(step.state.pendingJoin == nil)
        #expect(step.state.localOrigin[Fixtures.s2] == .preexisting)
        #expect(step.state.replica.live(Fixtures.s2).isEmpty)
    }

    @Test("Hotkeys that would share a combination at a join are one clash row")
    func clashRowAtJoin() throws {
        let env = environment(table: realTable)
        let hotkeys = Defaults.Key.hotkeys.rawValue
        let search = SyncUnitKey.split(family: hotkeys, item: "SearchMenuBarItems")
        let toggle = SyncUnitKey.split(family: hotkeys, item: "ToggleHiddenSection")
        let combination = SyncValue.data(HotkeyStorage.encode(key: 4, modifiers: 8))
        let entry = Fixtures.entry(Fixtures.macB, 5, combination)
        let theirs = file(contents(Fixtures.macB, Fixtures.replica([search: [entry]])))
        let step = join(joiner([toggle: combination]), SyncFolderRead(files: [theirs]), environment: env)
        let asked = try #require(question(step, environment: env))
        let row = try #require(asked.rows.first { $0.unit == search })
        #expect(row.style == .clash(partner: toggle))
        #expect(row.local == nil)
        #expect(asked.shown[search] == [entry.dot])
        #expect(asked.shown[toggle] == [])
        #expect(!committed(step))
    }

    @Test("The identity is settled before the join commits: an own file of another installation re-identifies")
    func identityAtJoin() {
        let clone = file(contents(Fixtures.macA, Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 8, .string("clone"))]]), installation: "another"))
        let step = join(joiner([Fixtures.s1: .string("clone")]), SyncFolderRead(files: [clone]))
        #expect(step.state.mac == fresh.mac)
        #expect(step.effects.contains { if case .storeIdentity(let mac, _) = $0 { mac == fresh.mac } else { false } })
        // The value is equal to the old identity's entry: adopted, no question.
        #expect(question(step) == nil)
        #expect(committed(step))
    }
}
