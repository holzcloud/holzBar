//
//  MergeTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncMerge")
struct MergeTests {
    private typealias Fixtures = SyncFixtures

    private let fresh = SyncFreshIdentity(mac: SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!, nonce: "fresh-nonce")

    private func contents(_ mac: SyncMacID, installation: String? = nil, _ replica: SyncReplica) -> SyncDeviceFile.Contents {
        SyncDeviceFile.Contents(unitTable: 1, mac: mac, installation: installation ?? "nonce-\(mac.rawValue.prefix(1))", written: Fixtures.now, replica: replica)
    }

    private func file(_ contents: SyncDeviceFile.Contents) -> SyncFileOutcome {
        SyncFileOutcome(macID: contents.mac, size: 200, modified: Fixtures.now, state: .contents(contents))
    }

    private func merge(_ files: [SyncFileOutcome], into state: SyncState, environment: SyncEnvironment? = nil, availability: SyncFolderAvailability = .available) -> SyncMergeResult {
        SyncMerge.merge(SyncFolderRead(availability: availability, files: files), into: state, environment: environment ?? Fixtures.environment())
    }

    // MARK: Join

    @Test("Files are joined in any order, with duplicates and older copies, to the same state")
    func orderDoesNotMatter() {
        let one = Fixtures.entry(Fixtures.macB, 3, .string("b"))
        let two = Fixtures.entry(Fixtures.macC, 4, .string("c"))
        let older = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macB, 1, .string("old"))]]))
        let newer = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [one]], extraContext: [Fixtures.macB: 3]))
        let other = contents(Fixtures.macC, Fixtures.replica([Fixtures.s2: [two]]))
        let state = Fixtures.state()
        let reference = merge([file(older), file(newer), file(other)], into: state).state.replica
        for files in [[other, newer, older], [newer, other, newer, older, other], [older, older, other, newer]] {
            // Two files of one Mac cannot be listed together; the repeats are separate reads.
            var current = state
            for item in files {
                current = merge([file(item)], into: current).state
            }
            #expect(current.replica == reference)
        }
        #expect(reference.live(Fixtures.s1).map(\.dot.n) == [3])
        #expect(reference.live(Fixtures.s2).map(\.dot.n) == [4])
    }

    @Test("A merge never removes an entry because a file lacks it; only a covering context removes it")
    func onlyAContextRemoves() {
        var state = Fixtures.state()
        let held = Fixtures.entry(Fixtures.macC, 4, .string("c"))
        state.replica = Fixtures.replica([Fixtures.s1: [held]])
        let lacking = contents(Fixtures.macB, Fixtures.replica([:], extraContext: [Fixtures.macB: 2]))
        #expect(merge([file(lacking)], into: state).state.replica.live(Fixtures.s1) == [held])
        let covering = contents(Fixtures.macB, Fixtures.replica([:], extraContext: [Fixtures.macB: 2, Fixtures.macC: 9]))
        #expect(merge([file(covering)], into: state).state.replica.live(Fixtures.s1).isEmpty)
    }

    @Test("An empty read and an unreadable folder change nothing")
    func emptyAndUnavailableReadsChangeNothing() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macC, 4, .string("c"))]])
        let empty = merge([], into: state)
        #expect(empty.state.replica == state.replica)
        #expect(!empty.replicaChanged)
        for availability in [SyncFolderAvailability.unavailable, .unusable] {
            let away = merge([], into: state, availability: availability)
            #expect(away.state.replica == state.replica)
            #expect(away.state.session.availability == availability)
            #expect(away.state.session.ownFile == .unread)
            #expect(!away.needsHealing)
        }
    }

    // MARK: Identity

    @Test("An own dot above the published counter that a file's context covers re-identifies first, keeping the replica")
    func reuseCheckReidentifies() {
        var state = Fixtures.state()
        let unpublished = Fixtures.entry(Fixtures.macA, 10, .string("mine"))
        state.replica = Fixtures.replica([Fixtures.s1: [unpublished]])
        state.publishedCounter = 5
        state.counter = 10
        state.applied[Fixtures.s1] = [unpublished.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("mine").digest
        // Another Mac's file has seen (A, 10) although this Mac never published it.
        let theirs = Fixtures.entry(Fixtures.macB, 3, .string("b"))
        let foreign = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [theirs]], extraContext: [Fixtures.macA: 10]))
        let result = merge([file(foreign)], into: state, environment: Fixtures.environment(freshIdentity: fresh))
        #expect(result.reidentified)
        #expect(result.state.mac == fresh.mac)
        #expect(result.state.nonce == fresh.nonce)
        #expect(result.state.previousMacIDs == [Fixtures.macA])
        #expect(result.state.applied[Fixtures.s1] == [unpublished.dot])
        #expect(result.state.baseline[Fixtures.s1] == SyncValue.string("mine").digest)
        #expect(result.state.localOrigin[Fixtures.s1] == .preexisting)
        #expect(result.state.published == SyncPublishedRecord())
        // The file is joined after the identity changed.
        #expect(result.state.replica.live(Fixtures.s1) == [theirs])
        #expect(result.state.session.ownFile == .absent)
    }

    @Test("An own file of another installation re-identifies")
    func otherInstallationReidentifies() {
        let state = Fixtures.state()
        let cloned = contents(Fixtures.macA, installation: "another-installation", Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 8, .string("clone"))]]))
        let result = merge([file(cloned)], into: state, environment: Fixtures.environment(freshIdentity: fresh))
        #expect(result.reidentified)
        #expect(result.state.mac == fresh.mac)
        // The old identity's file is another Mac's file now: its entry arrives as a waiting value.
        #expect(result.state.replica.live(Fixtures.s1).map(\.dot.mac) == [Fixtures.macA])
        #expect(result.state.isOwn(Fixtures.macA))
    }

    @Test("An own dot with other bytes in any file re-identifies")
    func ownDotWithOtherBytesReidentifies() {
        var state = Fixtures.state()
        let mine = Fixtures.entry(Fixtures.macA, 10, .string("mine"))
        state.replica = Fixtures.replica([Fixtures.s1: [mine]])
        state.publishedCounter = 10
        let forged = Fixtures.entry(Fixtures.macA, 10, .string("someone else's"))
        let foreign = contents(Fixtures.macC, Fixtures.replica([Fixtures.s1: [forged]]))
        let result = merge([file(foreign)], into: state, environment: Fixtures.environment(freshIdentity: fresh))
        #expect(result.reidentified)
        #expect(result.state.mac == fresh.mac)
        #expect(result.state.localOrigin[Fixtures.s1] == .preexisting)
        // Both values stay live: the collision is a question, never a silent pick.
        #expect(result.state.replica.distinctValues(Fixtures.s1).count == 2)
    }

    @Test("A conflict copy of the own file re-identifies, a conflict copy of another Mac's file changes nothing")
    func conflictCopies() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 4, .string("mine"))]])
        state.publishedCounter = 4
        let copyOfOwn = SyncFileOutcome(macID: nil, state: .conflictCopy(owner: Fixtures.macA))
        let copyOfOther = SyncFileOutcome(macID: nil, state: .conflictCopy(owner: Fixtures.macB))
        let environment = Fixtures.environment(freshIdentity: fresh)
        let other = merge([copyOfOther], into: state, environment: environment)
        #expect(!other.reidentified)
        #expect(other.state.mac == Fixtures.macA)
        #expect(other.state.replica == state.replica)
        let own = merge([copyOfOwn], into: state, environment: environment)
        #expect(own.reidentified)
        #expect(own.state.mac == fresh.mac)
    }

    @Test("Without a fresh identity a suspicious file is left out of the join")
    func noFreshIdentityLeavesTheFileOut() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 10, .string("mine"))]])
        state.publishedCounter = 5
        let theirs = Fixtures.entry(Fixtures.macB, 3, .string("b"))
        let foreign = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [theirs]], extraContext: [Fixtures.macA: 10]))
        let clean = contents(Fixtures.macC, Fixtures.replica([Fixtures.s2: [Fixtures.entry(Fixtures.macC, 2, .string("c"))]]))
        let result = merge([file(foreign), file(clean)], into: state)
        #expect(!result.reidentified)
        #expect(result.state.mac == Fixtures.macA)
        #expect(result.state.replica.live(Fixtures.s1).map(\.dot.mac) == [Fixtures.macA])
        #expect(result.state.replica.live(Fixtures.s2).count == 1)
    }

    @Test("An own file that is ahead of the state is joined first and raises the counter floor")
    func ownFileAheadOfTheState() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = SyncDigest.unset
        let later = Fixtures.entry(Fixtures.macA, 500, .string("later"))
        let ownFile = contents(Fixtures.macA, installation: state.nonce, Fixtures.replica([Fixtures.s1: [later]]))
        // Another Mac has read that file already; its context covers the dot.
        let relay = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [later]], extraContext: [Fixtures.macB: 2]))
        let result = merge([file(relay), file(ownFile)], into: state, environment: Fixtures.environment(freshIdentity: fresh))
        #expect(!result.reidentified)
        #expect(result.state.mac == Fixtures.macA)
        #expect(result.state.counter >= 500)
        #expect(result.state.publishedCounter == 500)
        #expect(result.state.replica.live(Fixtures.s1) == [later])
        #expect(result.state.session.ownFile == .read(digest: ownFile.replica.digest, isDominated: true))
        // It arrives as a fast-forward, and the next counter is above the highest own counter seen.
        let snapshot = Fixtures.snapshot()
        #expect(SyncPlan.plan(state: result.state, snapshot: snapshot, environment: Fixtures.environment()).outcomes[Fixtures.s1] == .fastForward)
        let minted = SyncCapture.capture(Fixtures.snapshot([Fixtures.s2: .string("x")]), state: result.state, environment: Fixtures.environment(unixSeconds: 10))
        #expect(minted.replica.live(Fixtures.s2)[0].dot.n > 500)
    }

    // MARK: Refusals

    @Test("A refused file is left out whole, recorded under its Mac and never read as missing")
    func refusedFileIsLeftOut() {
        var state = Fixtures.state()
        let held = Fixtures.entry(Fixtures.macB, 3, .string("b"))
        state.replica = Fixtures.replica([Fixtures.s1: [held]])
        let refused = SyncFileOutcome(macID: Fixtures.macB, size: 2_000_000, modified: Fixtures.now, state: .refused(.tooLarge(2_000_000)))
        let result = merge([refused], into: state)
        #expect(result.state.replica == state.replica)
        #expect(result.state.refusals[Fixtures.macB.rawValue]?.reason == SyncRefusal.tooLarge(0).code)
        #expect(result.state.refusals[Fixtures.macB.rawValue]?.size == 2_000_000)
        #expect(!result.reidentified)
        // The record holds the Mac's identity, never a file name.
        #expect(result.state.refusals.keys.allSatisfy { SyncMacID($0) != nil })
        // A later read that finds the file readable forgets the refusal.
        let readable = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [held]]))
        #expect(merge([file(readable)], into: result.state).state.refusals.isEmpty)
    }

    @Test("A newer format adds the status line, and an own file of a newer format is never written over")
    func newerFormatIsNeverRewritten() {
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 3, .string("mine"))]])
        let newer = SyncFileOutcome(macID: Fixtures.macA, size: 300, modified: Fixtures.now, state: .refused(.newerFormat(2)))
        let result = merge([newer], into: state).state
        #expect(SyncEngine.view(of: result, environment: Fixtures.environment()).lines.contains(.newerFormat))
        #expect(result.session.ownFile == .unread)
        guard case .none(.ownFileNotRead) = SyncPublish.decision(state: result, environment: Fixtures.environment(), trigger: .relay) else {
            Issue.record("the own file of a newer format must not be written")
            return
        }
    }

    @Test("A refusal lasts after ten minutes of the same size and date; a changed file starts over")
    func lastingRefusals() {
        let state = Fixtures.state()
        let refusedOwn = SyncFileOutcome(macID: Fixtures.macA, size: 100, modified: Fixtures.now, state: .refused(.wrongStructure("root")))
        let start = Fixtures.environment(freshIdentity: fresh)
        let first = merge([refusedOwn], into: state, environment: start)
        #expect(!first.reidentified)
        let soon = Fixtures.environment(freshIdentity: fresh, now: Fixtures.now.addingTimeInterval(9 * 60))
        #expect(!merge([refusedOwn], into: first.state, environment: soon).reidentified)
        let later = Fixtures.environment(freshIdentity: fresh, now: Fixtures.now.addingTimeInterval(11 * 60))
        let lasting = merge([refusedOwn], into: first.state, environment: later)
        #expect(lasting.reidentified)
        #expect(lasting.state.mac == fresh.mac)
        // A file whose size changed in between is a new refusal.
        let grown = SyncFileOutcome(macID: Fixtures.macA, size: 120, modified: Fixtures.now, state: .refused(.wrongStructure("root")))
        #expect(!merge([grown], into: first.state, environment: later).reidentified)
    }

    @Test("Another Mac's lasting refusal never re-identifies this Mac")
    func otherMacsRefusalDoesNotReidentify() {
        let refused = SyncFileOutcome(macID: Fixtures.macB, size: 100, modified: Fixtures.now, state: .refused(.notPropertyList))
        let first = merge([refused], into: Fixtures.state(), environment: Fixtures.environment(freshIdentity: fresh))
        let later = Fixtures.environment(freshIdentity: fresh, now: Fixtures.now.addingTimeInterval(3_600))
        let second = merge([refused], into: first.state, environment: later)
        #expect(!second.reidentified)
        #expect(second.state.mac == Fixtures.macA)
        #expect(second.state.refusals[Fixtures.macB.rawValue]?.firstSeen == Fixtures.now)
    }

    @Test("A dataless or pending file is never lasting, requests its download and counts as waiting")
    func datalessAndPendingFiles() {
        let dataless = SyncFileOutcome(macID: Fixtures.macB, size: 0, state: .dataless)
        let pending = SyncFileOutcome(macID: Fixtures.macC, size: 10, state: .pending)
        let ownDataless = SyncFileOutcome(macID: Fixtures.macA, size: 0, state: .dataless)
        let later = Fixtures.environment(freshIdentity: fresh, now: Fixtures.now.addingTimeInterval(3_600))
        let first = merge([dataless, pending, ownDataless], into: Fixtures.state(), environment: Fixtures.environment(freshIdentity: fresh))
        #expect(first.downloads == [Fixtures.macA, Fixtures.macB])
        #expect(first.state.session.waitingFiles == 3)
        #expect(first.state.session.ownFile == .unread)
        let second = merge([dataless, pending, ownDataless], into: first.state, environment: later)
        #expect(!second.reidentified)
        #expect(second.state.refusals.isEmpty)
    }

    @Test("When more files are listed than the limit, the skipped count shows and the values still arrive through relays")
    func skippedFiles() {
        let relayed = Fixtures.entry(Fixtures.macC, 4, .string("from a skipped Mac"))
        let relay = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [relayed]], extraContext: [Fixtures.macB: 1]))
        let read = SyncFolderRead(files: [file(relay)], skipped: 3)
        let result = SyncMerge.merge(read, into: Fixtures.state(), environment: Fixtures.environment())
        #expect(result.state.session.skippedFiles == 3)
        #expect(SyncEngine.view(of: result.state, environment: Fixtures.environment()).lines.contains(.skippedFiles(3)))
        #expect(result.state.replica.live(Fixtures.s1) == [relayed])
    }

    // MARK: Own file and publish

    /// A state whose own file was read in this session and holds exactly what the state holds.
    private func published(_ state: SyncState, environment: SyncEnvironment = Fixtures.environment()) -> SyncState {
        var state = state
        state.published = SyncPublishedRecord(replicaDigest: state.replica.digest, ownFileDigest: state.replica.digest)
        state.publishedCounter = state.replica.context[state.mac]
        state.session.ownFile = .read(digest: state.replica.digest, isDominated: true)
        return state
    }

    private func replicaWithOwnEntry() -> SyncReplica {
        Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 10, .string("mine"))]])
    }

    /// A consistent state of Mac A that minted (A, 10) for S1, with the defaults still holding it.
    private func stateWithOwnEntry() -> SyncState {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        state.counter = 10
        state.applied[Fixtures.s1] = [SyncDot(mac: Fixtures.macA, n: 10)]
        state.baseline[Fixtures.s1] = SyncValue.string("mine").digest
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")])
        return state
    }

    @Test("A read that finds the own file or the whole folder missing changes nothing locally and leads to a healing write")
    func missingOwnFileHeals() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        state = published(state)
        let result = merge([], into: state)
        #expect(result.state.replica == state.replica)
        #expect(result.needsHealing)
        #expect(result.state.session.ownFile == .absent)
        guard case .write(let request) = SyncPublish.decision(state: result.state, environment: Fixtures.environment(), trigger: .healing) else {
            Issue.record("the missing own file must be written again")
            return
        }
        #expect(request.expectation == .absent)
        #expect(request.contents.replica == state.replica)
    }

    @Test("An own file that is older than what was written is joined and healed")
    func olderOwnFileHeals() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        state = published(state)
        let restored = contents(Fixtures.macA, installation: state.nonce, Fixtures.replica([:]))
        let result = merge([file(restored)], into: state)
        #expect(result.needsHealing)
        #expect(result.state.replica == state.replica)
        guard case .write(let request) = SyncPublish.decision(state: result.state, environment: Fixtures.environment(), trigger: .healing) else {
            Issue.record("the older own file must be written over")
            return
        }
        #expect(request.expectation == .readThisSession(digest: restored.replica.digest))
    }

    @Test("A replica that equals what was published with an intact own file writes nothing")
    func unchangedWritesNothing() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        state = published(state)
        guard case .none(.unchanged) = SyncPublish.decision(state: state, environment: Fixtures.environment(), trigger: .relay) else {
            Issue.record("an unchanged state must not write")
            return
        }
        let intact = contents(Fixtures.macA, installation: state.nonce, state.replica)
        let read = merge([file(intact)], into: state)
        #expect(!read.needsHealing)
        #expect(!read.replicaChanged)
        guard case .none(.unchanged) = SyncPublish.decision(state: read.state, environment: Fixtures.environment(), trigger: .healing) else {
            Issue.record("an intact own file must not be written again")
            return
        }
    }

    @Test("Nothing is written before the own file is read, while a join is pending, while the folder is away or when the file is too large")
    func publishPreconditions() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        let environment = Fixtures.environment()
        func skip(_ state: SyncState, _ environment: SyncEnvironment = environment) -> SyncWriteSkip? {
            if case .none(let reason) = SyncPublish.decision(state: state, environment: environment, trigger: .ownChange) {
                return reason
            }
            return nil
        }
        #expect(skip(state) == .ownFileNotRead)
        var read = state
        read.session.ownFile = .absent
        #expect(skip(read) == nil)
        var undominated = state
        undominated.session.ownFile = .read(digest: SyncDigest.hash([1]), isDominated: false)
        #expect(skip(undominated) == .ownFileNotDominated)
        var joining = read
        joining.pendingJoin = SyncPendingJoin(replica: .empty, shown: [:], isFounding: false, folderIdentity: nil)
        #expect(skip(joining) == .pendingJoin)
        var away = read
        away.session.availability = .unavailable
        #expect(skip(away) == .folderUnavailable)
        var off = read
        off.isEnabled = false
        #expect(skip(off) == .disabled)
        // The encoded size is checked before anything is written.
        var huge = read
        huge.replica = Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macA, 10, .string(String(repeating: "x", count: 2 << 20)))]])
        #expect(skip(huge) == .tooLarge)
        // Nothing to publish yet.
        var empty = Fixtures.state()
        empty.session.ownFile = .absent
        #expect(skip(empty) == .nothingToPublish)
    }

    @Test("Without the own-file-first guard the write does not wait for a read and checks nothing")
    func withoutOwnFileGuard() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        let control = Fixtures.environment(guards: SyncGuards.all.subtracting(.ownFileReadFirst))
        guard case .write(let request) = SyncPublish.decision(state: state, environment: control, trigger: .ownChange) else {
            Issue.record("the control engine writes without a read")
            return
        }
        #expect(request.expectation == .unchecked)
    }

    @Test("After a write that reads back intact the counter and both digests are recorded; a failed one keeps them")
    func writeResults() {
        var state = Fixtures.state()
        state.replica = replicaWithOwnEntry()
        state.counter = 10
        state.session.ownFile = .absent
        guard case .write(let request) = SyncPublish.decision(state: state, environment: Fixtures.environment(), trigger: .ownChange) else {
            Issue.record("a state with an unpublished entry must write")
            return
        }
        #expect(request.counter == 10)
        let failed = SyncPublish.apply(.failed(.unavailable), to: state)
        #expect(failed.publishedCounter == 0)
        #expect(failed.published == SyncPublishedRecord())
        let unverified = SyncPublish.apply(.unverified, to: state)
        #expect(unverified.publishedCounter == 0)
        #expect(unverified.session.ownFile == .unread)
        let receipt = SyncWriteReceipt(counter: request.counter, replicaDigest: request.replicaDigest, fileDigest: request.replicaDigest)
        let verified = SyncPublish.apply(.verified(receipt), to: state)
        #expect(verified.publishedCounter == 10)
        #expect(verified.published == SyncPublishedRecord(replicaDigest: request.replicaDigest, ownFileDigest: request.replicaDigest))
        #expect(verified.session.ownFile == .read(digest: request.replicaDigest, isDominated: true))
        // And now nothing is left to write.
        guard case .none(.unchanged) = SyncPublish.decision(state: verified, environment: Fixtures.environment(), trigger: .relay) else {
            Issue.record("a verified write leaves nothing to write")
            return
        }
    }

    @Test("The file carries the whole replica: relays, unknown units and unknown fields are written unchanged")
    func passThrough() throws {
        var state = Fixtures.state()
        let future = SyncEntry(
            dot: SyncDot(mac: Fixtures.macC, n: 7),
            at: Fixtures.now,
            payload: .value(.dictionary(["shape": .string("new")])),
            extra: ["note": .string("from a newer build")]
        )
        state.replica = Fixtures.replica([
            .whole("FromTheFuture"): [future],
            .split(family: "FutureFamily", item: "x"): [Fixtures.entry(Fixtures.macB, 3, .integer(4))],
            Fixtures.s1: [Fixtures.entry(Fixtures.macA, 10, .string("mine"))],
        ])
        state.session.ownFile = .absent
        guard case .write(let request) = SyncPublish.decision(state: state, environment: Fixtures.environment(), trigger: .ownChange) else {
            Issue.record("expected a write")
            return
        }
        let data = try SyncDeviceFile.encode(request.contents)
        let decoded = try SyncDeviceFile.decode(data, fileName: "\(Fixtures.macA.rawValue).plist").get()
        #expect(decoded.replica == state.replica)
        #expect(decoded.replica.live(.whole("FromTheFuture")) == [future])
        // The context claims only dots this Mac has seen, and every live entry is covered by it.
        for key in decoded.replica.keys {
            for entry in decoded.replica.live(key) {
                #expect(decoded.replica.context.covers(entry.dot))
            }
        }
        #expect(decoded.replica.context.macs == [Fixtures.macA, Fixtures.macB, Fixtures.macC])
    }

    // MARK: Legacy

    @Test("The legacy file's writer shows the older-holzBar line for 30 days, and never decides anything")
    func legacyMetadata() {
        var state = Fixtures.state()
        state.legacy.foundingDigest = SyncDigest.hash([1])
        state.legacy.legacyDeviceID = "OLD-ID-OF-THIS-MAC"
        let changed = Fixtures.now.addingTimeInterval(-3_600)
        let foreign = SyncLegacyFile(modified: changed, deviceID: "ANOTHER", settings: [:], identityDigest: SyncDigest.hash([2]))
        let read = SyncFolderRead(legacy: .file(foreign))
        let result = SyncMerge.merge(read, into: state, environment: Fixtures.environment())
        #expect(result.state.legacy.lastLegacyChange == changed)
        #expect(SyncEngine.view(of: result.state, environment: Fixtures.environment()).lines.contains(.olderHolzBar))
        // The same digest as at founding changes nothing, and this Mac's own legacy writes are ignored.
        let same = SyncLegacyFile(modified: changed, deviceID: "ANOTHER", settings: [:], identityDigest: SyncDigest.hash([1]))
        #expect(SyncMerge.merge(SyncFolderRead(legacy: .file(same)), into: state, environment: Fixtures.environment()).state.legacy.lastLegacyChange == nil)
        let own = SyncLegacyFile(modified: changed, deviceID: "OLD-ID-OF-THIS-MAC", settings: [:], identityDigest: SyncDigest.hash([2]))
        #expect(SyncMerge.merge(SyncFolderRead(legacy: .file(own)), into: state, environment: Fixtures.environment()).state.legacy.lastLegacyChange == nil)
        // 30 days later the line is gone, and the replica never changed.
        let late = Fixtures.environment(now: changed.addingTimeInterval(31 * 24 * 3600))
        #expect(!SyncEngine.view(of: result.state, environment: late).lines.contains(.olderHolzBar))
        #expect(result.state.replica == state.replica)
    }

    @Test("The legacy file is not read before founding, and afterwards only its metadata")
    func legacyRequests() {
        var state = Fixtures.state()
        state.isEnabled = true
        func request(_ state: SyncState) -> SyncReadRequest? {
            for effect in SyncEngine.handle(.timer(.check), state: state, environment: Fixtures.environment()).effects {
                if case .readFolder(let request) = effect {
                    return request
                }
            }
            return nil
        }
        #expect(request(state)?.legacy == SyncLegacyRequest.none)
        state.legacy.foundingDigest = SyncDigest.hash([1])
        #expect(request(state)?.legacy == .metadata)
    }

    // MARK: Engine flow

    private func effectNames(_ step: SyncStep) -> [String] {
        step.effects.map { effect in
            switch effect {
            case .applyUnits: "apply"
            case .persist: "persist"
            case .readFolder: "read"
            case .writeOwnFile: "write"
            case .schedule(let timer, _): "schedule-\(timer)"
            case .cancelTimer: "cancel"
            case .relaunch: "relaunch"
            case .requestDownload: "download"
            }
        }
    }

    @Test("A change is persisted before the own file is written")
    func persistBeforeWrite() {
        var state = Fixtures.state()
        state.session.ownFile = .absent
        let environment = Fixtures.environment()
        let changed = SyncEngine.handle(.defaultsChanged(Fixtures.snapshot([Fixtures.s1: .string("new")])), state: state, environment: environment)
        #expect(effectNames(changed) == ["schedule-capture"])
        let fired = SyncEngine.handle(.timer(.capture), state: changed.state, environment: environment)
        #expect(effectNames(fired) == ["persist", "write"])
        #expect(fired.state.generation == state.generation + 1)
        guard case .persist(let persist) = fired.effects[0], case .write(let request) = SyncPublish.decision(state: fired.state, environment: environment, trigger: .ownChange) else {
            Issue.record("expected a persist and a write")
            return
        }
        #expect(persist.counter == fired.state.counter)
        #expect(request.contents.replica.live(Fixtures.s1).count == 1)
    }

    @Test("A merge that changes the replica schedules a relay; a missing own file schedules healing; an unchanged read schedules nothing")
    func readSchedules() {
        var state = Fixtures.state()
        state.session.snapshot = Fixtures.snapshot()
        let environment = Fixtures.environment()
        let theirs = contents(Fixtures.macB, Fixtures.replica([Fixtures.s1: [Fixtures.entry(Fixtures.macB, 3, .string("b"))]]))
        let relay = SyncEngine.handle(.folderRead(SyncFolderRead(files: [file(theirs)]), purpose: .check), state: state, environment: environment)
        #expect(effectNames(relay) == ["persist", "schedule-relay"])
        #expect(SyncEngine.view(of: relay.state, environment: environment).hint == .restart)

        let healing = published(stateWithOwnEntry())
        let missing = SyncEngine.handle(.folderRead(SyncFolderRead(), purpose: .check), state: healing, environment: environment)
        #expect(effectNames(missing) == ["schedule-healing"])

        // A relaunch with nothing changed: Sigma decodes, the own file reads back intact, nothing happens.
        var relaunched = healing
        relaunched.session = SyncSession()
        relaunched.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")])
        let intact = contents(Fixtures.macA, installation: healing.nonce, healing.replica)
        let quiet = SyncEngine.handle(.folderRead(SyncFolderRead(files: [file(intact)]), purpose: .launch), state: relaunched, environment: environment)
        #expect(quiet.effects.isEmpty)
        #expect(SyncEngine.view(of: quiet.state, environment: environment).hint == nil)
    }

    @Test("Restart applies the fast-forwards, persists, writes what is unpublished and relaunches in this order")
    func restartOrder() {
        var state = Fixtures.state()
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("old")])
        state.baseline[Fixtures.s1] = SyncValue.string("old").digest
        state.replica = Fixtures.replica([Fixtures.s2: [Fixtures.entry(Fixtures.macB, 3, .string("b"))]])
        let step = SyncEngine.handle(.command(.restart), state: state, environment: Fixtures.environment())
        #expect(effectNames(step) == ["apply", "persist", "write", "relaunch"])
        guard case .applyUnits(let changes) = step.effects[0] else {
            Issue.record("expected an apply")
            return
        }
        #expect(changes == [Fixtures.s2: .value(.string("b"))])
        #expect(step.state.applied[Fixtures.s2] == [SyncDot(mac: Fixtures.macB, n: 3)])
        #expect(step.state.baseline[Fixtures.s2] == SyncValue.string("b").digest)
        #expect(step.state.session.snapshot?.values[Fixtures.s2] == .string("b"))
        // The relayed entry is written before the relaunch, so nothing waits in memory.
        #expect(SyncEngine.view(of: step.state, environment: Fixtures.environment()).hint == nil)
    }

    @Test("A write that fails because the own file changed makes the engine read it again")
    func ownFileChangedReadsAgain() {
        var state = Fixtures.state()
        state.session.ownFile = .read(digest: SyncDigest.hash([3]), isDominated: true)
        let step = SyncEngine.handle(.writeFinished(.failed(.ownFileChanged)), state: state, environment: Fixtures.environment())
        #expect(step.state.session.ownFile == .unread)
        #expect(effectNames(step) == ["schedule-check"])
    }
}
