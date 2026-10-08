//
//  IdentityTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncIdentity")
struct IdentityTests {
    private let hardware = "9B2F6C1A-1111-4222-8333-444455556666"
    private let salt = Data(repeating: 7, count: 32)
    private let uid: UInt32 = 501
    private let ownID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let otherID = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
    private let freshID = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func mac(_ string: String) throws -> SyncMacID {
        try #require(SyncMacID(string))
    }

    // MARK: Hash

    @Test("The same hardware, user and salt give the same hash; another user gives another")
    func hashDependsOnUser() {
        let one = SettingsSyncDevice.hardwareHash(of: hardware, uid: 501, salt: salt)
        #expect(one == SettingsSyncDevice.hardwareHash(of: hardware, uid: 501, salt: salt))
        #expect(one != SettingsSyncDevice.hardwareHash(of: hardware, uid: 502, salt: salt))
        #expect(one != SettingsSyncDevice.hardwareHash(of: hardware, salt: salt))
        #expect(one.count == 64)
        #expect(!one.contains(hardware))
        #expect(!one.lowercased().contains(hardware.lowercased()))
    }

    // MARK: Decision

    @Test("The same hardware and user keep the identity")
    func sameIdentity() throws {
        let hash = SettingsSyncDevice.hardwareHash(of: hardware, uid: uid, salt: salt)
        let decision = SyncIdentity.check(storedID: ownID, storedHash: hash, salt: salt, hardwareID: hardware, uid: uid) { SyncMacID(UUID()) }
        #expect(decision == .same(try mac(ownID)))
    }

    @Test("A copied account on the same Mac gets another identity")
    func copiedAccount() throws {
        let hash = SettingsSyncDevice.hardwareHash(of: hardware, uid: 501, salt: salt)
        let decision = SyncIdentity.check(storedID: ownID, storedHash: hash, salt: salt, hardwareID: hardware, uid: 502) { (try? mac(freshID)) ?? SyncMacID(UUID()) }
        #expect(decision == .rotated(new: try mac(freshID), legacyID: ownID))
    }

    @Test("A hash without the user rotates once; the next launch finds the new hash")
    func oldHashRotatesOnce() throws {
        let old = SettingsSyncDevice.hardwareHash(of: hardware, salt: salt)
        let first = SyncIdentity.check(storedID: ownID, storedHash: old, salt: salt, hardwareID: hardware, uid: uid) { (try? mac(freshID)) ?? SyncMacID(UUID()) }
        guard case .rotated(let new, let legacy) = first else {
            Issue.record("Expected a rotation, got \(first)")
            return
        }
        #expect(new == (try mac(freshID)))
        #expect(legacy == ownID)
        let hash = SettingsSyncDevice.hardwareHash(of: hardware, uid: uid, salt: salt)
        let second = SyncIdentity.check(storedID: new.rawValue, storedHash: hash, salt: salt, hardwareID: hardware, uid: uid) { SyncMacID(UUID()) }
        #expect(second == .same(new))
    }

    @Test("An identity without a hash rotates")
    func missingHash() throws {
        let decision = SyncIdentity.check(storedID: ownID, storedHash: nil, salt: nil, hardwareID: hardware, uid: uid) { (try? mac(freshID)) ?? SyncMacID(UUID()) }
        #expect(decision == .rotated(new: try mac(freshID), legacyID: ownID))
    }

    @Test("Without an identity this is the first run")
    func firstRun() throws {
        let decision = SyncIdentity.check(storedID: nil, storedHash: nil, salt: nil, hardwareID: hardware, uid: uid) { (try? mac(freshID)) ?? SyncMacID(UUID()) }
        #expect(decision == .firstRun(try mac(freshID)))
    }

    @Test("Without a hardware ID an existing identity stays")
    func noHardwareID() throws {
        let decision = SyncIdentity.check(storedID: ownID, storedHash: "x", salt: salt, hardwareID: nil, uid: uid) { SyncMacID(UUID()) }
        #expect(decision == .noHardwareID(try mac(ownID)))
    }

    @Test("A stored identity that is not an identity rotates")
    func malformedID() throws {
        let hash = SettingsSyncDevice.hardwareHash(of: hardware, uid: uid, salt: salt)
        let decision = SyncIdentity.check(storedID: "not-a-uuid", storedHash: hash, salt: salt, hardwareID: hardware, uid: uid) { (try? mac(freshID)) ?? SyncMacID(UUID()) }
        #expect(decision == .rotated(new: try mac(freshID), legacyID: "not-a-uuid"))
    }

    // MARK: Reuse

    private func state(counter: UInt64, published: UInt64, units: [String: UInt64]) throws -> SyncState {
        let own = try mac(ownID)
        var replica = SyncReplica()
        for (name, n) in units {
            let entry = SyncEntry(dot: SyncDot(mac: own, n: n), at: date, payload: .value(.integer(Int64(n))))
            replica = replica.setting(.whole(name), to: entry)
        }
        return SyncState(mac: own, nonce: "N1", counter: counter, publishedCounter: published, replica: replica)
    }

    @Test("Own live dots above the published counter that another file's context covers are suspect")
    func suspectDots() throws {
        let own = try mac(ownID)
        let other = try mac(otherID)
        let state = try state(counter: 12, published: 10, units: ["A": 9, "B": 11, "C": 12])
        let context = SyncContext(counters: [own: 11, other: 50])
        let suspect = SyncIdentity.suspectReusedDots(in: state, coveredBy: context)
        #expect(suspect == [SyncDot(mac: own, n: 11)])
    }

    @Test("Dots at or below the published counter are never suspect")
    func publishedDotsAreNotSuspect() throws {
        let own = try mac(ownID)
        let state = try state(counter: 12, published: 12, units: ["A": 9, "B": 11, "C": 12])
        #expect(SyncIdentity.suspectReusedDots(in: state, coveredBy: SyncContext(counters: [own: 100])).isEmpty)
    }

    @Test("Dots of other Macs are never suspect")
    func foreignDotsAreNotSuspect() throws {
        let own = try mac(ownID)
        let other = try mac(otherID)
        var state = try state(counter: 3, published: 0, units: [:])
        state.replica = state.replica.setting(.whole("X"), to: SyncEntry(dot: SyncDot(mac: other, n: 40), at: date, payload: .deleted))
        #expect(SyncIdentity.suspectReusedDots(in: state, coveredBy: SyncContext(counters: [own: 100, other: 100])).isEmpty)
    }

    @Test("A dot that a file's context covers while the file holds no entry for the unit is suspect, whatever the published counter says")
    func neverSeenDotsAreSuspect() throws {
        let own = try mac(ownID)
        let other = try mac(otherID)
        let state = try state(counter: 12, published: 12, units: ["A": 9, "B": 11])
        // The file has seen both dots, holds an entry for A (a later one of another Mac) and none for B.
        var replica = SyncReplica(context: SyncContext(counters: [own: 12, other: 50]))
        replica = replica.setting(.whole("A"), to: SyncEntry(dot: SyncDot(mac: other, n: 50), at: date, payload: .value(.integer(1))))
        let suspect = SyncIdentity.suspectCollidingDots(in: state, coveredBy: replica)
        #expect(suspect == [SyncDot(mac: own, n: 11)])
    }

    @Test("A dot that the own file holds or supersedes is no collision, a dot that it neither holds nor supersedes is")
    func ownFileExplainsDots() throws {
        let own = try mac(ownID)
        let other = try mac(otherID)
        let state = try state(counter: 12, published: 10, units: ["A": 11, "B": 12])
        // Another file has seen both dots and holds an entry of another Mac for each unit.
        var seen = SyncReplica(context: SyncContext(counters: [own: 12, other: 50]))
        seen = seen.setting(.whole("A"), to: SyncEntry(dot: SyncDot(mac: other, n: 50), at: date, payload: .value(.integer(1))))
        seen = seen.setting(.whole("B"), to: SyncEntry(dot: SyncDot(mac: other, n: 51), at: date, payload: .value(.integer(1))))
        // The own file holds A's entry as it is and has superseded nothing of B's.
        var ownFile = SyncReplica(context: SyncContext(counters: [own: 12]))
        ownFile = ownFile.setting(.whole("A"), to: SyncEntry(dot: SyncDot(mac: own, n: 11), at: date, payload: .value(.integer(11))))
        #expect(SyncIdentity.suspectCollidingDots(in: state, coveredBy: seen, ownFile: ownFile) == [SyncDot(mac: own, n: 12)])
        // Without the own file both dots above the published counter are suspect.
        #expect(SyncIdentity.suspectCollidingDots(in: state, coveredBy: seen).count == 2)
    }

    // MARK: Collision signals

    private func file(mac fileMac: String, installation: String, units: [String: (UInt64, Int64)]) throws -> SyncDeviceFile.Contents {
        let id = try mac(fileMac)
        var replica = SyncReplica()
        for (name, spec) in units {
            let entry = SyncEntry(dot: SyncDot(mac: id, n: spec.0), at: date, payload: .value(.integer(spec.1)))
            replica = replica.setting(.whole(name), to: entry)
        }
        return SyncDeviceFile.Contents(unitTable: 1, mac: id, installation: installation, written: date, replica: replica)
    }

    @Test("An own dot with another payload in a file is a collision")
    func ownDotWithOtherPayload() throws {
        let own = try mac(ownID)
        let state = try state(counter: 9, published: 9, units: ["A": 9])
        let clean = try file(mac: ownID, installation: "N1", units: ["A": (9, 9)])
        let signals = SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: clean, fileName: ownID + ".plist", state: state)
        #expect(signals.isEmpty)
        let forged = try file(mac: otherID, installation: "X", units: [:])
        var tampered = forged
        tampered.replica = SyncReplica(registers: [.whole("A"): [SyncEntry(dot: SyncDot(mac: own, n: 9), at: date, payload: .value(.integer(1000)))]])
        let tamperedSignals = SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: tampered, fileName: otherID + ".plist", state: state)
        #expect(tamperedSignals == [.ownDotWithOtherPayload(SyncDot(mac: own, n: 9))])
    }

    @Test("The own file with another installation nonce is a collision")
    func otherNonce() throws {
        let own = try mac(ownID)
        let state = try state(counter: 9, published: 9, units: ["A": 9])
        let foreign = try file(mac: ownID, installation: "N2", units: ["A": (9, 9)])
        let signals = SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: foreign, fileName: ownID + ".plist", state: state)
        #expect(signals == [.otherInstallation])
    }

    @Test("A conflict copy named after the own Mac is a collision")
    func conflictCopy() throws {
        let own = try mac(ownID)
        let state = try state(counter: 9, published: 9, units: ["A": 9])
        let copy = try file(mac: ownID, installation: "N1", units: ["A": (9, 9)])
        for name in [ownID + " 2.plist", ownID + " (conflicted copy).plist"] {
            let signals = SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: copy, fileName: name, state: state)
            #expect(signals == [.conflictCopy], "\(name)")
        }
    }

    @Test("A clean file of another Mac is never a signal")
    func otherMacFile() throws {
        let own = try mac(ownID)
        let state = try state(counter: 9, published: 9, units: ["A": 9])
        let other = try file(mac: otherID, installation: "N1", units: ["A": (40, 1)])
        #expect(SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: other, fileName: otherID + ".plist", state: state).isEmpty)
        let otherNonce = try file(mac: otherID, installation: "Z", units: [:])
        #expect(SyncIdentity.collisionSignals(ownMac: own, ownNonce: "N1", file: otherNonce, fileName: otherID + ".plist", state: state).isEmpty)
    }

    // MARK: Lasting refusals

    @Test("The same refusal for ten minutes with the file unchanged is lasting")
    func lastingRefusal() {
        let modified = date.addingTimeInterval(-3600)
        let record = SyncRefusalRecord(reason: SyncRefusal.notPropertyList.code, size: 100, modified: modified, firstSeen: date)
        #expect(SyncIdentity.isLastingRefusal(record, now: date.addingTimeInterval(600), size: 100, modified: modified))
        #expect(!SyncIdentity.isLastingRefusal(record, now: date.addingTimeInterval(599), size: 100, modified: modified))
    }

    @Test("A file that changes is not lasting")
    func changingFile() {
        let modified = date.addingTimeInterval(-3600)
        let record = SyncRefusalRecord(reason: SyncRefusal.wrongStructure("x").code, size: 100, modified: modified, firstSeen: date)
        let later = date.addingTimeInterval(3600)
        #expect(!SyncIdentity.isLastingRefusal(record, now: later, size: 101, modified: modified))
        #expect(!SyncIdentity.isLastingRefusal(record, now: later, size: 100, modified: modified.addingTimeInterval(1)))
        #expect(!SyncIdentity.isLastingRefusal(record, now: later, size: 100, modified: nil))
    }

    @Test("A partial, empty or dataless read is never lasting")
    func partialReads() {
        let record = SyncRefusalRecord(reason: SyncRefusal.unreadable.code, size: 100, modified: date, firstSeen: date)
        #expect(!SyncIdentity.isLastingRefusal(record, now: date.addingTimeInterval(86400), size: 100, modified: date))
        let empty = SyncRefusalRecord(reason: SyncRefusal.notPropertyList.code, size: 0, modified: date, firstSeen: date)
        #expect(!SyncIdentity.isLastingRefusal(empty, now: date.addingTimeInterval(86400), size: 0, modified: date))
    }

    // MARK: Re-identification

    @Test("Re-identification keeps the replica, applied and baseline and marks suspect units")
    func reidentification() throws {
        let own = try mac(ownID)
        let fresh = try mac(freshID)
        var state = try state(counter: 12, published: 10, units: ["A": 9, "B": 11])
        state.applied[.whole("A")] = [SyncDot(mac: own, n: 9)]
        state.baseline[.whole("A")] = SyncValue.integer(9).digest
        state.baseline[.whole("B")] = SyncValue.integer(11).digest
        state.published = SyncPublishedRecord(replicaDigest: SyncValue.integer(1).digest, ownFileDigest: nil)
        let suspect = [SyncDot(mac: own, n: 11)]
        let result = SyncIdentity.reidentified(state, newMac: fresh, newNonce: "N2", suspect: suspect)
        #expect(result.mac == fresh)
        #expect(result.nonce == "N2")
        #expect(result.previousMacIDs == [own])
        #expect(result.replica == state.replica)
        #expect(result.applied == state.applied)
        #expect(result.baseline == state.baseline)
        #expect(result.localOrigin == [.whole("B"): .preexisting])
        #expect(result.published == SyncPublishedRecord())
        #expect(result.counter == state.counter)
    }

    @Test("Re-identifying twice remembers both old identities once")
    func reidentifyTwice() throws {
        let own = try mac(ownID)
        let fresh = try mac(freshID)
        let third = try mac(otherID)
        let state = try state(counter: 1, published: 1, units: [:])
        let once = SyncIdentity.reidentified(state, newMac: fresh, newNonce: "N2", suspect: [])
        let twice = SyncIdentity.reidentified(once, newMac: third, newNonce: "N3", suspect: [])
        #expect(twice.previousMacIDs == [own, fresh])
        let same = SyncIdentity.reidentified(twice, newMac: third, newNonce: "N4", suspect: [])
        #expect(same.previousMacIDs == [own, fresh])
        #expect(same.localOrigin.isEmpty)
    }
}
