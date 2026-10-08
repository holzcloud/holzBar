//
//  StateCodecTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncState")
struct StateCodecTests {
    private let macA = SyncMacID("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
    private let macB = SyncMacID("BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func fullState() throws -> SyncState {
        let idA = try #require(macA)
        let idB = try #require(macB)
        let hotkey = SyncUnitKey.split(family: "Hotkeys", item: "ShowHidden")
        let whole = SyncUnitKey.whole("ShowOnHover")
        let dot = SyncDot(mac: idA, n: 4)
        let replica = SyncReplica(
            context: SyncContext(counters: [idA: 4, idB: 2]),
            registers: [
                whole: [SyncEntry(dot: dot, at: date, payload: .value(.bool(true)))],
                hotkey: [SyncEntry(dot: SyncDot(mac: idB, n: 2), at: date, payload: .deleted, extra: ["x": .integer(1)])],
            ],
            sets: ["Seen": ["a"]]
        )
        var state = SyncState(mac: idA, nonce: "nonce")
        state.counter = 4
        state.publishedCounter = 3
        state.generation = 11
        state.replica = replica
        state.applied = [whole: [dot], hotkey: []]
        state.baseline = [whole: SyncValue.bool(true).digest, hotkey: .unset]
        state.localOnly = [whole: .oversize, hotkey: .invalid]
        state.localOrigin = [whole: .automatic, hotkey: .preexisting]
        state.pendingJoin = SyncPendingJoin(
            replica: SyncReplica(context: SyncContext(counters: [idB: 2])),
            shown: [hotkey: [SyncDot(mac: idB, n: 2)]],
            isFounding: true,
            folderIdentity: "folder"
        )
        state.legacy = SyncLegacyRecord(
            lastSyncedSeen: date,
            foundingDigest: SyncValue.string("legacy").digest,
            legacyDeviceID: "OLD-ID",
            lastLegacyChange: date.addingTimeInterval(5)
        )
        state.published = SyncPublishedRecord(replicaDigest: replica.digest, ownFileDigest: SyncValue.string("file").digest)
        state.laterLaunch = 6
        state.launchCount = 9
        state.refusals = [idB.rawValue: SyncRefusalRecord(reason: SyncRefusal.tooLarge(5).code, size: 2_000_000, modified: date, firstSeen: date)]
        state.previousMacIDs = [idB]
        state.isEnabled = true
        state.systemGeneration = .g27
        return state
    }

    @Test("A state round-trips with every field")
    func roundTrip() throws {
        let state = try fullState()
        let data = try SyncStateCodec.encode(state)
        guard case .state(let decoded) = SyncStateCodec.decode(data) else {
            Issue.record("The state did not decode")
            return
        }
        #expect(decoded == state)
    }

    @Test("A fresh state round-trips")
    func freshState() throws {
        let state = SyncState(mac: try #require(macA), nonce: "n")
        guard case .state(let decoded) = SyncStateCodec.decode(try SyncStateCodec.encode(state)) else {
            Issue.record("The state did not decode")
            return
        }
        #expect(decoded == state)
        #expect(decoded.format == SyncState.currentFormat)
        #expect(!decoded.isEnabled)
    }

    @Test("A state of a newer format is named, not read")
    func newerFormat() throws {
        var state = try fullState()
        state.format = 2
        let data = try SyncStateCodec.encode(state)
        #expect(SyncStateCodec.decode(data) == .newerFormat(2))
    }

    @Test("Damaged bytes are unreadable, never an empty state")
    func damaged() throws {
        let data = try SyncStateCodec.encode(try fullState())
        #expect(SyncStateCodec.decode(Data()) == .unreadable)
        #expect(SyncStateCodec.decode(Data([1, 2, 3, 4, 5, 6, 7, 8])) == .unreadable)
        #expect(SyncStateCodec.decode(data.dropLast(16)) == .unreadable)
        let array = try PropertyListSerialization.data(fromPropertyList: [1], format: .binary, options: 0)
        #expect(SyncStateCodec.decode(array) == .unreadable)
        let empty = try PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)
        #expect(SyncStateCodec.decode(empty) == .unreadable)
    }

    @Test("A state with a field of the wrong type is unreadable")
    func wrongField() throws {
        let data = try SyncStateCodec.encode(try fullState())
        var object = try #require(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        object["counter"] = "four"
        let damaged = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        #expect(SyncStateCodec.decode(damaged) == .unreadable)
    }
}
